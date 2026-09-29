#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
#
# Put a freshly built kernel into an existing update tarball, so a kernel
# change can go onto the device without rebuilding the rest of the system.
#
#   kernel-update.sh export <outdir>
#       In the build container, after "scripts/build_mt linux". Copies the
#       boot image, System.map and the modules out of linux's install
#       directory, stripped the way scripts/image strips them.
#
#   kernel-update.sh repack <base.tar> <exportdir> <outdir> <suffix>
#       On the runner, which needs sudo. Swaps target/KERNEL and the in-tree
#       modules inside target/SYSTEM, redoes what scripts/image does to the
#       modules afterwards, and writes <outdir>/<name>-<suffix>.tar and its
#       .sha256.
#
# The update tarball is <name>/target/{KERNEL,SYSTEM}{,.md5}. The init
# script's updater extracts */target/* and checks each .md5, which names its
# file as target/KERNEL or target/SYSTEM, so both are rewritten that way.

set -e -o pipefail

die() {
  echo "kernel-update: $*" >&2
  exit 1
}

cmd_export() {
  local out="${1:?usage: kernel-update.sh export <outdir>}"
  local inst modroot modver

  . config/options ""

  inst="$(get_install_dir linux)"
  modroot="${inst}/$(get_kernel_overlay_dir)/lib/modules"
  [ -f "${inst}/.image/${KERNEL_TARGET}" ] || die "no ${KERNEL_TARGET} in ${inst}/.image: was linux built?"
  [ "$(ls -1 "${modroot}" | wc -l)" -eq 1 ] || die "expected one kernel version under ${modroot}"
  modver="$(ls -1 "${modroot}")"

  rm -rf "${out}"
  mkdir -p "${out}/modules"
  cp -p "${inst}/.image/${KERNEL_TARGET}" "${out}/KERNEL"
  cp -p "${inst}/.image/System.map" "${out}/System.map"
  cp -a "${modroot}/${modver}" "${out}/modules/"
  echo "${modver}" > "${out}/MODVER"

  # scripts/image strips every module after installing it; do the same, with
  # the same tool, so the modules differ from a full build's only where the
  # source did.
  find "${out}/modules" -type f -name '*.ko' -exec ${TARGET_KERNEL_PREFIX}strip --strip-debug {} +

  echo "kernel-update: exported ${KERNEL_TARGET} and $(find "${out}/modules" -name '*.ko' | wc -l) modules for ${modver}"
}

cmd_repack() {
  set -u
  local base="${1:?usage: kernel-update.sh repack <base.tar> <exportdir> <outdir> <suffix>}"
  local exp="${2:?}" out="${3:?}" suffix="${4:?}"
  local work name newname sysdir moddir modver info comp bs level f

  [ -f "${exp}/KERNEL" ] && [ -f "${exp}/MODVER" ] || die "${exp} is not an export"
  modver="$(cat "${exp}/MODVER")"

  work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/kernel-update.XXXXXX")"
  # KU_WORK is global on purpose: an EXIT trap runs after this function has
  # returned, when its locals are gone, and under set -u reading one fails.
  KU_WORK="${work}"
  trap 'sudo rm -rf "${KU_WORK:-}"' EXIT

  tar -xf "${base}" -C "${work}"
  [ "$(ls -1 "${work}" | wc -l)" -eq 1 ] || die "${base} does not have exactly one top-level directory"
  name="$(ls -1 "${work}")"
  [ -f "${work}/${name}/target/KERNEL" ] && [ -f "${work}/${name}/target/SYSTEM" ] ||
    die "${base} has no target/KERNEL and target/SYSTEM"

  # Read the compressor and block size back out of the base image rather than
  # restating them, so the repack cannot drift from whatever the project sets.
  # Levels are the ones scripts/image uses for each compressor.
  info="$(sudo unsquashfs -s "${work}/${name}/target/SYSTEM")"
  comp="$(awk '/^Compression /{print $2; exit}' <<<"${info}")"
  bs="$(awk '/^Block size /{print $3; exit}' <<<"${info}")"
  case "${comp}" in
    gzip|lzo) level="-Xcompression-level 9" ;;
    zstd)     level="-Xcompression-level 19" ;;
    *)        level="" ;;
  esac
  [ -n "${comp}" ] && [ -n "${bs}" ] || die "could not read compression from the base SYSTEM"

  # As root, so ownership and modes come back exactly as recorded.
  sysdir="${work}/system"
  sudo unsquashfs -no-progress -d "${sysdir}" "${work}/${name}/target/SYSTEM" >/dev/null

  moddir="${sysdir}/usr/lib/kernel-overlays/base/lib/modules"
  if [ ! -d "${moddir}/${modver}" ]; then
    die "the base carries modules for $(ls -1 "${moddir}" | tr '\n' ' ')and this kernel is ${modver}. Out-of-tree modules built for the old version would not load. This needs a full build."
  fi

  # In-tree modules live under kernel/. Everything else in the directory is
  # either an out-of-tree module, carried over (it still loads, the version is
  # unchanged), or depmod output, regenerated below.
  sudo rm -rf "${moddir}/${modver}/kernel"
  sudo cp -a "${exp}/modules/${modver}/kernel" "${moddir}/${modver}/"
  for f in modules.builtin modules.builtin.modinfo modules.builtin.ranges; do
    [ -f "${exp}/modules/${modver}/${f}" ] && sudo cp -a "${exp}/modules/${modver}/${f}" "${moddir}/${modver}/"
  done
  # Exported by the build user; the image has them as root, like everything
  # else fakeroot put there.
  sudo chown -R 0:0 "${moddir}/${modver}"

  # What scripts/image does after installing modules: modules.order from
  # every .ko present, then depmod against this kernel's System.map.
  (cd "${moddir}/${modver}" && sudo find . -name '*.ko' | sed -e 's,^\./,,') |
    sudo tee "${moddir}/${modver}/modules.order" >/dev/null
  sudo depmod -b "${sysdir}/usr/lib/kernel-overlays/base" -a -e -F "${exp}/System.map" "${modver}"

  newname="${name}-${suffix}"
  mv "${work}/${name}" "${work}/${newname}"
  rm -f "${work}/${newname}/target/SYSTEM"
  sudo mksquashfs "${sysdir}" "${work}/${newname}/target/SYSTEM" -noappend \
    -comp "${comp}" ${level} -b "${bs}" -no-progress >/dev/null
  sudo chown "$(id -u):$(id -g)" "${work}/${newname}/target/SYSTEM"
  cp "${exp}/KERNEL" "${work}/${newname}/target/KERNEL"
  chmod 0644 "${work}/${newname}/target/KERNEL" "${work}/${newname}/target/SYSTEM"

  (
    cd "${work}/${newname}"
    md5sum -t target/SYSTEM >target/SYSTEM.md5
    md5sum -t target/KERNEL >target/KERNEL.md5
  )

  mkdir -p "${out}"
  tar cf "${out}/${newname}.tar" -C "${work}" "${newname}"
  (cd "${out}" && sha256sum "${newname}.tar" >"${newname}.tar.sha256")

  echo "kernel-update: ${out}/${newname}.tar (${comp}, block ${bs}, kernel ${modver})"
}

# Prove the repack changed nothing it had no business changing: the md5 files
# check, the compressor and block size match the base, and every path outside
# this kernel's module directory has the same owner, mode and size as before.
cmd_verify() {
  set -u
  local base="${1:?usage: kernel-update.sh verify <base.tar> <new.tar>}" new="${2:?}"
  local work a b modver skip
  work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/kernel-verify.XXXXXX")"
  KU_WORK="${work}"
  trap 'sudo rm -rf "${KU_WORK:-}"' EXIT

  mkdir "${work}/a" "${work}/b"
  tar -xf "${base}" -C "${work}/a"
  tar -xf "${new}" -C "${work}/b"
  a="${work}/a/$(ls -1 "${work}/a")"
  b="${work}/b/$(ls -1 "${work}/b")"

  (cd "${b}" && md5sum -c --quiet target/KERNEL.md5 target/SYSTEM.md5) || die "md5 check failed"

  for f in "${a}" "${b}"; do
    sudo unsquashfs -s "${f}/target/SYSTEM" | awk '/^Compression |^Block size /'
  done | sort | uniq -c | awk '$1 != 2 {bad=1} END {exit bad}' ||
    die "compression or block size differs from the base"

  modver="$(sudo unsquashfs -lln "${b}/target/SYSTEM" |
    sed -n 's,.*/usr/lib/kernel-overlays/base/lib/modules/\([^/]*\)$,\1,p' | head -1)"
  [ -n "${modver}" ] || die "no module directory in the new SYSTEM"
  skip="usr/lib/kernel-overlays/base/lib/modules/${modver}/"

  # -lln: numeric owner, mode and size per path. Dates are dropped, since
  # mksquashfs stamps directories it rewrote.
  for f in a b; do
    sudo unsquashfs -lln "${work}/${f}/$(ls -1 "${work}/${f}")/target/SYSTEM" |
      awk -v skip="${skip}" '{
        # mode owner size date time path[ -> target]: take everything after
        # the fifth field as the path, so symlinks and spaces survive.
        rest = $0
        for (i = 1; i <= 5; i++) sub(/^[^ ]+ +/, "", rest)
        if (rest !~ /^squashfs-root/) next
        sub(/^squashfs-root\/?/, "", rest)
        path = rest; sub(/ -> .*/, "", path)
        if (index(path, skip) == 1) next
        print $1, $2, ($1 ~ /^d/ ? "-" : $3), rest
      }' | sort >"${work}/${f}.list"
  done
  if ! diff -q "${work}/a.list" "${work}/b.list" >/dev/null; then
    diff "${work}/a.list" "${work}/b.list" | head -20 >&2
    die "files outside ${skip} differ from the base"
  fi

  echo "kernel-update: verified. md5s check, compression matches, $(wc -l <"${work}/a.list") paths outside ${skip} unchanged."
}

case "${1:-}" in
  export) shift; cmd_export "$@" ;;
  repack) shift; cmd_repack "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  *) echo "usage: kernel-update.sh {export <outdir> | repack <base.tar> <exportdir> <outdir> <suffix> | verify <base.tar> <new.tar>}" >&2; exit 2 ;;
esac
