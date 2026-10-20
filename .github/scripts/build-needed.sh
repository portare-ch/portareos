#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Does anything in this ref actually affect a build, since the last time we
# built it successfully?
#
# A commit that only touches documentation costs exactly as much CI time as one
# that rewrites the kernel config, because nothing looks. This answers the
# question so an automatic trigger can decline to spend five hours proving that
# a README edit still builds.
#
# It deliberately does NOT gate workflow_dispatch. A human who clicked "Run
# workflow" asked for a build, and silently not producing an image would be a
# worse surprise than a wasted runner. The caller decides; this only reports.
#
# Fails closed in every direction: no previous run, an unreachable API, a
# missing commit, a diff that cannot be taken, or any path it does not
# positively recognise as inert all print "yes".
#
# Prints "yes" or "no". Never exits non-zero.

set -uo pipefail

WORKFLOW="${1:-build-nightly.yml}"

say() { printf '%s\n' "$1"; exit 0; }

[ -n "${GITHUB_REPOSITORY:-}" ] || say yes
[ -n "${GITHUB_REF_NAME:-}" ]   || say yes

# The head of the last green build of this branch is the last tree we know
# produced an image, which is the only sensible thing to diff against.
last="$(gh api \
  "repos/${GITHUB_REPOSITORY}/actions/workflows/${WORKFLOW}/runs?status=success&branch=${GITHUB_REF_NAME}&per_page=1" \
  --jq '.workflow_runs[0].head_sha' 2>/dev/null || true)"

case "${last}" in
  ""|null) echo "build-needed: no previous successful build to compare against." >&2; say yes ;;
esac

if ! git cat-file -e "${last}^{commit}" 2>/dev/null; then
  echo "build-needed: ${last} is not in this checkout (shallow clone?)." >&2
  say yes
fi

changed="$(git diff --name-only "${last}" HEAD 2>/dev/null)" || say yes

if [ -z "${changed}" ]; then
  echo "build-needed: tree identical to the last successful build." >&2
  say no
fi

# An allowlist, not a blocklist. Everything that is not named here counts as
# build-affecting, so a new top-level directory fails towards building.
#
# Note *.md is inert only because a package README changing would, at worst,
# move that package's stamp and rebuild it - never change what the image does.
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  case "${f}" in
    documentation/*|docs/*|*.md|.github/ISSUE_TEMPLATE/*|LICENSE.md|.gitignore|\
    tools/build-docs.py|.github/workflows/docs.yml)
      continue ;;
    *)
      echo "build-needed: ${f} affects the build." >&2
      say yes ;;
  esac
done <<< "${changed}"

echo "build-needed: only inert paths changed since ${last}." >&2
say no
