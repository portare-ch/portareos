#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Cross-run build state for the CI stages allowed to build incrementally.
#
# The buildsystem already decides, per package, whether a rebuild is needed:
# scripts/build hashes each package's recipe and patches (calculate_stamp) and
# skips the package when that hash matches the one recorded in
# .stamps/<pkg>/build_<target>. In CI the mechanism never fires, because
# .stamps and install_pkg live only inside the per-run artifacts and the
# purge-artifact job deletes all of them at the end of every build. Every run
# therefore starts with an empty .stamps, every stamp is missing, and every
# package rebuilds. This script gives that mechanism a memory across runs.
#
# The safety problem it has to solve: calculate_stamp hashes a package's own
# files only, and scripts/build returns "already built" before PKG_DEPENDS_* is
# even read, so changing a dependency does not rebuild its dependents.
# Restoring a stage's state blindly would keep emulators that were built
# against a library which has since changed - a green run producing an image
# full of mismatched binaries.
#
# So the restore is gated on the upstream surface. "snapshot" runs after the
# upstream stage artifacts are unpacked and hashes the stamps they brought;
# that is exactly the set of dependency recipes this stage is about to build
# against. The saved archive records the same digest from the run that produced
# it, and the two must match or the archive is ignored and the stage builds
# cold. Edit SDL2 and its stamp content changes, the digests diverge, and every
# dependent stage rebuilds by itself.
#
# "snapshot" also records which install_* entries arrived from upstream, so
# "save" can archive only the packages this stage actually contributes rather
# than a copy of everything its dependencies installed.
#
# Nothing here may fail a build: a missing, truncated or mismatched archive is
# a cold build, never an error.
#
# Root stages (build-arm, build-aarch64-toolchain) have no upstream stage to
# gate on: they start from a bare checkout, so there are no upstream stamps and
# the digest above is always "no-stamps". They use the -root variants instead,
# which gate on the recipes themselves. "save-root" records the package names
# that were built and a digest over exactly the files calculate_stamp would
# hash for them; "restore-root" recomputes that digest from the current
# checkout and refuses the archive unless it matches. Change gcc's recipe and
# the toolchain rebuilds; change an emulator's and it does not.
#
# The one hole in that gate is a package newly pulled into the stage's
# dependency closure, since it cannot be in a list saved before it existed.
# It closes in practice: the dependency has to be declared in some recipe that
# *is* in the list, so that recipe's files change and the digest moves anyway.
#
# Usage:
#   build-state.sh snapshot     <build-dir>                     # prints the digest
#   build-state.sh restore      <build-dir> <asset-base> <digest>
#   build-state.sh save         <build-dir> <asset-base> <digest>
#   build-state.sh restore-root <build-dir> <asset-base> [--ignore-recipes]
#   build-state.sh save-root    <build-dir> <asset-base> {<path>... | -T <file>}
#
# Environment:
#   CACHE_REPO  owner/repo holding the "ccache" release  (restore only)
#   PROJECT     project name, for resolving recipe paths  (-root only)
#   DEVICE      device name, for resolving recipe paths   (-root only)

set -euo pipefail

DIGEST_FILE=".build-state-digest"
UPSTREAM_LIST=".build-state-upstream-list"
UPSTREAM_TC_LIST=".build-state-upstream-toolchain-list"
TOOLCHAIN_MARKER=".build-state-has-toolchain"
RECIPE_LIST=".build-state-recipes"
# Enough parts for any archive we produce; each is capped below GitHub's 2 GB
# per-asset limit.
SUFFIXES="aa ab ac ad ae af ag ah ai aj ak al"

# A digest over the stamp files only. They are tiny, and their contents are the
# recorded deephashes, so this changes exactly when some package's recipe
# changed - and not when an unchanged package merely gets rebuilt.
stamp_digest() {
  local build_dir="$1"

  # No stamps at all - nothing upstream to compare against. Emit a value that
  # cannot match any saved digest, so the restore falls back to a cold build.
  # Guarding this also matters mechanically: under "set -o pipefail" a find
  # over a missing directory fails the pipeline and would fail the step.
  if [ ! -d "${build_dir}/.stamps" ]; then
    echo "no-stamps"
    return 0
  fi

  find "${build_dir}/.stamps" -type f -name 'build_*' -print0 2>/dev/null \
    | LC_ALL=C sort -z \
    | xargs -0 -r sha256sum \
    | sha256sum \
    | cut -d' ' -f1
}

# Depth-1 entries of every install_* directory, as they stand right now.
install_entries() {
  local build_dir="$1"
  find "${build_dir}" -maxdepth 1 -type d -name 'install_*' \
    -exec find {} -mindepth 1 -maxdepth 1 \; 2>/dev/null | LC_ALL=C sort
}

# Every file and symlink under toolchain/, as they stand right now. A package's
# build output has three homes: install_* for the image, toolchain/ for host
# packages, and toolchain/<triple>/sysroot for the headers and libraries other
# packages build against. Saving only install_* produced restored trees where
# SDL2's stamp said built, its image files were there, and there was no SDL.h
# for amiberry to compile against.
toolchain_entries() {
  local build_dir="$1"
  find "${build_dir}/toolchain" -mindepth 1 \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort
}

cmd_snapshot() {
  local build_dir="$1"
  install_entries "${build_dir}" > "${UPSTREAM_LIST}"
  toolchain_entries "${build_dir}" > "${UPSTREAM_TC_LIST}"
  echo "build-state: $(wc -l < "${UPSTREAM_LIST}") install entries and $(wc -l < "${UPSTREAM_TC_LIST}") toolchain files came from upstream." >&2
  stamp_digest "${build_dir}"
}

# Pull every part of an asset and concatenate them into state.tar. Returns
# non-zero when nothing was there, which every caller treats as a cold build.
fetch_parts() {
  local asset="$1"
  local base="https://github.com/${CACHE_REPO}/releases/download/ccache"
  local n=0 s

  for s in ${SUFFIXES}; do
    curl -L --fail --silent --show-error -o "${asset}.part-${s}" \
      "${base}/${asset}.part-${s}" || break
    n=$((n + 1))
  done

  if [ "${n}" -eq 0 ]; then
    rm -f "${asset}".part-* 2>/dev/null || true
    return 1
  fi

  cat "${asset}".part-* > state.tar
  rm -f "${asset}".part-*
  return 0
}

# A saved state is only valid in the checkout it was built in. Build output
# is full of that path spelled out absolutely: meson's sysroot dev links, the
# fakeroot wrapper's library search path, host tools' rpaths into
# toolchain/lib. When the repository became portareos the runner's checkout
# moved from /home/runner/work/distribution/distribution to .../portareos/
# portareos, and every archive saved before that restored a tree pointing
# into a directory that no longer exists. Repointing the symlinks got the
# build as far as the image, where fakeroot aborted on its own wrapper script;
# rpaths cannot be rewritten at all when the old and new paths differ in
# length. So the path is recorded next to the digest and a mismatch is
# treated like any other one: build cold, once, and save a state that is
# right for where it will be restored.
build_root() {
  realpath -m "$1"
}

cmd_restore() {
  local build_dir="$1" asset="$2" want="$3"
  local have have_root

  if ! fetch_parts "${asset}"; then
    echo "build-state: no saved state for ${asset} - building cold."
    return 0
  fi

  if ! tar -xf state.tar "./${DIGEST_FILE}" 2>/dev/null; then
    rm -f state.tar
    echo "build-state: archive carries no digest - building cold."
    return 0
  fi

  have="$(sed -n 1p "${DIGEST_FILE}")"
  have_root="$(sed -n 2p "${DIGEST_FILE}")"
  rm -f "${DIGEST_FILE}"

  if [ "${have_root}" != "$(build_root "${build_dir}")" ]; then
    rm -f state.tar
    echo "build-state: saved under ${have_root:-an unrecorded path}, this checkout is $(build_root "${build_dir}") - building cold."
    return 0
  fi

  if [ "${have}" != "${want}" ]; then
    rm -f state.tar
    echo "build-state: upstream changed since this state was saved - building cold."
    echo "  saved against ${have}"
    echo "  now           ${want}"
    return 0
  fi

  # A package's build output has three homes: install_* for the image,
  # toolchain/ for host packages, and toolchain/<triple>/sysroot for what
  # other packages build against. Archives saved before cmd_save learned to
  # carry the toolchain/ part hold stamps for packages whose output is only
  # partly present: kmod:host with no toolchain/bin/kmod, SDL2 with its image
  # files but no SDL.h. scripts/build trusts the stamp and skips the package,
  # nothing provides the rest, and the failure lands packages later, in
  # amiberry or in scripts/image calling depmod. Such an archive cannot be
  # used at all. Building cold once is what produces a complete one.
  if ! tar -tf state.tar "./${TOOLCHAIN_MARKER}" >/dev/null 2>&1; then
    rm -f state.tar
    echo "build-state: archive predates toolchain/ output and is incomplete - building cold."
    return 0
  fi

  # The digests match, so every stamp in the archive is byte-identical to the
  # one the upstream artifacts just delivered; extracting over them is a no-op,
  # and this stage's own stamps, packages and toolchain additions come back.
  echo "build-state: upstream unchanged - restoring ${asset}."
  tar -xf state.tar || echo "build-state: extract failed - building cold."
  rm -f state.tar "${TOOLCHAIN_MARKER}"

  echo "build-state: $(find "${build_dir}/.stamps" -type f -name 'build_*' 2>/dev/null | wc -l) stamps now present."
}

cmd_save() {
  local build_dir="$1" asset="$2" digest="$3"
  local list=".build-state-save-list"

  # Everything installed that did not come from upstream is ours: what this
  # stage built this run, plus whatever a restore brought back.
  if [ -f "${UPSTREAM_LIST}" ]; then
    install_entries "${build_dir}" | LC_ALL=C comm -23 - "${UPSTREAM_LIST}" > "${list}"
  else
    echo "build-state: no upstream snapshot - saving every install entry." >&2
    install_entries "${build_dir}" > "${list}"
  fi

  # Whatever this stage added under toolchain/: host package binaries and the
  # sysroot headers and libraries its target packages installed. Files the
  # upstream artifacts already had are left out, since they arrive with those
  # artifacts on the next run. A file upstream had and this stage rewrote in
  # place is not caught; nothing in the tree does that today.
  if [ -f "${UPSTREAM_TC_LIST}" ]; then
    toolchain_entries "${build_dir}" | LC_ALL=C comm -23 - "${UPSTREAM_TC_LIST}" >> "${list}"
  else
    echo "build-state: no upstream toolchain snapshot - saving every toolchain file." >&2
    toolchain_entries "${build_dir}" >> "${list}"
  fi

  printf '%s\n%s\n' "${digest}" "$(build_root "${build_dir}")" > "${DIGEST_FILE}"
  printf '%s\n' "./${DIGEST_FILE}" >> "${list}"

  # Tells restore that this archive carries toolchain output, so the stamps
  # for host packages in it can be trusted.
  : > "${TOOLCHAIN_MARKER}"
  printf '%s\n' "./${TOOLCHAIN_MARKER}" >> "${list}"
  printf '%s\n' "${build_dir}/.stamps" >> "${list}"

  echo "build-state: archiving $(wc -l < "${list}") paths."
  tar -cf - -T "${list}" | split -b 1900m - "${asset}.part-"
  rm -f "${DIGEST_FILE}" "${TOOLCHAIN_MARKER}" "${list}"
  ls -la "${asset}".part-*
}

# The files calculate_stamp (config/functions) would hash for one package: its
# recipe directory plus the project and device patch directories. find can
# also return a category directory that shares the package's name, which makes
# this a superset of what the buildsystem hashes: it errs towards rebuilding
# and never away from it.
recipe_paths() {
  local name="$1" d
  find packages -type d -name "${name}" 2>/dev/null || true
  for d in "projects/${PROJECT}/patches/${name}" \
           "projects/${PROJECT}/devices/${DEVICE}/patches/${name}"; do
    [ -d "${d}" ] && printf '%s\n' "${d}"
  done
  return 0
}

# Always folded in, whichever packages a stage built. config/ and scripts/ are
# the buildsystem itself, and the options files carry the variables the seven
# packages that set PKG_STAMP interpolate into their stamps (KERNEL_TARGET,
# UBOOT_SYSTEM), which recipe_paths alone would not see.
#
# Except config/emulators/, which recipe_digest leaves out: it is not
# buildsystem but the data es_systems.cfg is generated from, read by one
# package - emulators, whose stamp covers it through PKG_NEED_UNPACK. Folded
# in here, a line changed in movies.conf refused the saved toolchain and
# rebuilt gcc and glibc from cold.
global_surface() {
  local d
  for d in config scripts distributions \
           "projects/${PROJECT}/options" \
           "projects/${PROJECT}/devices/${DEVICE}/options"; do
    [ -e "${d}" ] && printf '%s\n' "${d}"
  done
  return 0
}

# A digest over the recipes behind a list of package names, computed from the
# working tree. Same shape as calculate_stamp: hash each file, sorted by path.
recipe_digest() {
  local list="$1" name d
  local -a paths=()

  while IFS= read -r d; do
    [ -n "${d}" ] && paths+=("${d}")
  done < <(global_surface)

  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    while IFS= read -r d; do
      [ -n "${d}" ] && paths+=("${d}")
    done < <(recipe_paths "${name}")
  done < "${list}"

  # Nothing to hash cannot be allowed to look like a match: emit a value no
  # saved digest can equal, so the caller builds cold.
  if [ ${#paths[@]} -eq 0 ]; then
    echo "no-recipes"
    return 0
  fi

  # The host architecture belongs in the digest even though it is not a
  # recipe. A root stage's archive carries build.../toolchain, which is host
  # binaries - the compiler this build runs, not the one it produces. Restored
  # onto a host of a different architecture those cannot execute, and because
  # the build container installs qemu-user-binfmt on aarch64 hosts they would
  # not even fail cleanly: they would run under emulation, correctly and
  # perhaps a hundred times too slowly, with nothing in the log to say why.
  #
  # Folding uname -m in makes state saved on one host architecture refuse
  # itself on another, which is the whole safety property needed to move
  # between runner architectures. No asset renaming, and no way to forget it.
  #
  # sort -zu collapses the duplicates that fall out of resolving both the local
  # and the global copy of a recipe.
  { printf 'host-arch %s\n' "$(uname -m)"
    find -L "${paths[@]}" -type f -not -name '.*' \
      -not -path 'config/emulators/*' -print0 2>/dev/null \
      | LC_ALL=C sort -zu \
      | xargs -0 -r sha256sum
  } | sha256sum | cut -d' ' -f1
}

cmd_restore_root() {
  local build_dir="$1" asset="$2" ignore_recipes="${3:-}"
  local have have_root want

  if ! fetch_parts "${asset}"; then
    echo "build-state: no saved state for ${asset} - building cold."
    return 0
  fi

  if ! tar --zstd -xf state.tar "./${DIGEST_FILE}" "./${RECIPE_LIST}" 2>/dev/null; then
    rm -f state.tar "${DIGEST_FILE}" "${RECIPE_LIST}"
    echo "build-state: archive carries no recipe manifest - building cold."
    return 0
  fi

  have="$(sed -n 1p "${DIGEST_FILE}")"
  have_root="$(sed -n 2p "${DIGEST_FILE}")"
  want="$(recipe_digest "${RECIPE_LIST}")"
  rm -f "${DIGEST_FILE}" "${RECIPE_LIST}"

  if [ "${have_root}" != "$(build_root "${build_dir}")" ]; then
    rm -f state.tar
    echo "build-state: saved under ${have_root:-an unrecorded path}, this checkout is $(build_root "${build_dir}") - building cold."
    return 0
  fi

  if [ "${have}" != "${want}" ]; then
    # --ignore-recipes is for the kernel-only workflow, which exists precisely
    # because a kernel patch moves the toolchain stage's digest (glibc builds
    # against linux:host) without changing anything the toolchain is made of.
    # Restoring anyway is not blind: every package whose own recipe moved still
    # rebuilds, because its stamp no longer matches. What it accepts is that
    # packages built on top of a moved one are not rebuilt with it, which is
    # the whole point for glibc and a device-tree patch. Only the caller knows
    # that is safe, so only the caller can ask for it.
    if [ "${ignore_recipes}" = "--ignore-recipes" ]; then
      echo "build-state: recipes changed since this state was saved - restoring anyway (--ignore-recipes)."
      echo "  saved against ${have}"
      echo "  now           ${want}"
    else
      rm -f state.tar
      echo "build-state: recipes changed since this state was saved - building cold."
      echo "  saved against ${have}"
      echo "  now           ${want}"
      return 0
    fi
  else
    echo "build-state: recipes unchanged - restoring ${asset}."
  fi

  tar --zstd -xf state.tar || echo "build-state: extract failed - building cold."
  # The full extract puts the two metadata files back into the checkout; they
  # have served their purpose and save-root writes them fresh.
  rm -f state.tar "${DIGEST_FILE}" "${RECIPE_LIST}"
  echo "build-state: $(find "${build_dir}/.stamps" -type f -name 'build_*' 2>/dev/null | wc -l) stamps now present."
}

cmd_save_root() {
  local build_dir="$1" asset="$2"; shift 2
  local digest

  if [ ! -d "${build_dir}/.stamps" ]; then
    echo "build-state: no stamps to describe - not saving."
    return 0
  fi

  # The package names this stage ended up with are the closure it actually
  # built, which is a better list than anything we could enumerate by hand.
  find "${build_dir}/.stamps" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | LC_ALL=C sort > "${RECIPE_LIST}"

  digest="$(recipe_digest "${RECIPE_LIST}")"
  printf '%s\n%s\n' "${digest}" "$(build_root "${build_dir}")" > "${DIGEST_FILE}"
  echo "build-state: $(wc -l < "${RECIPE_LIST}") packages, recipe digest ${digest}."

  # "-T <file>" for a stage whose archive set is easier to compute than to
  # spell out; build-arm already builds such a list to pack its artifact, and
  # archiving exactly the artifact's contents is what makes a restored tree
  # indistinguishable from one this stage just built.
  if [ "${1:-}" = "-T" ]; then
    cat "$2" >> "${RECIPE_LIST}.paths"
    printf '%s\n' "./${DIGEST_FILE}" "./${RECIPE_LIST}" >> "${RECIPE_LIST}.paths"
    tar --zstd -cf - -T "${RECIPE_LIST}.paths" | split -b 1900m - "${asset}.part-"
    rm -f "${RECIPE_LIST}.paths"
  else
    tar --zstd -cf - "./${DIGEST_FILE}" "./${RECIPE_LIST}" "$@" \
      | split -b 1900m - "${asset}.part-"
  fi
  rm -f "${DIGEST_FILE}" "${RECIPE_LIST}"
  ls -la "${asset}".part-*
}

case "${1:-}" in
  snapshot) shift; cmd_snapshot "$@" ;;
  restore)  shift; cmd_restore  "$@" ;;
  save)     shift; cmd_save     "$@" ;;
  restore-root) shift; cmd_restore_root "$@" ;;
  save-root)    shift; cmd_save_root    "$@" ;;
  *) echo "usage: build-state.sh {snapshot|restore|save|restore-root|save-root} ..." >&2; exit 2 ;;
esac
