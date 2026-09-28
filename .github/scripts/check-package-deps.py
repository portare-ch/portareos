#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Check that every package named in a PKG_DEPENDS_* line exists in the tree.
#
# This expands variables rather than reading the dependency strings literally,
# because recipes routinely build the list up in a local variable first:
#
#   PKG_TOOLS="patchelf i2c-tools evtest"
#   PKG_DEPENDS_TARGET+=" ${PKG_TOOLS} ${PKG_FONTS} misc-packages"
#
# and virtual/emulators names every libretro core and standalone emulator
# through PKG_EMUS and LIBRETRO_CORES rather than through dependencies at all.
#
# A checker that only matches literal names inside PKG_DEPENDS_* sees none of
# that. It reports a clean tree while a deleted package sits waiting to fail
# the build in genbuildplan.py, after the container pull and the toolchain
# stage. That is exactly how evtest was removed along with the Kodi-era addons
# and not noticed until build-aarch64 failed.
#
# Run from the repository root. Exits non-zero if anything dangles.

import collections
import os
import re
import sys

# Leading whitespace is allowed: virtual/emulators builds LIBRETRO_CORES up
# inside case branches, indented, and a column-0 match saw none of those.
ASSIGN = re.compile(r'^\s*([A-Z_][A-Z0-9_]*)\s*\+?=\s*"([^"]*)"', re.M | re.S)
DEPEND = re.compile(r'PKG_DEPENDS_[A-Z]+\s*\+?=\s*"([^"]*)"', re.S)
VARREF = re.compile(r'\$\{([A-Z_][A-Z0-9_]*)\}')


def load():
    names, recipes = set(), []
    for root, dirs, files in os.walk("."):
        if ".git" in root.split(os.sep) or "package.mk" not in files:
            continue
        path = os.path.join(root, "package.mk")
        text = open(path, encoding="utf-8", errors="replace").read()
        m = re.search(r'^PKG_NAME="([^"]+)"', text, re.M)
        names.add(m.group(1) if m else os.path.basename(root))
        recipes.append((path, text))
    return names, recipes


def dangling(names, recipes):
    missing = collections.defaultdict(set)
    for path, text in recipes:
        env = collections.defaultdict(str)
        for key, value in ASSIGN.findall(text):
            env[key] += " " + value
        for block in DEPEND.findall(text):
            # Two passes, so a list that references another list resolves.
            for _ in range(2):
                block = VARREF.sub(lambda m: env.get(m.group(1), ""), block)
            for token in block.split():
                token = token.split(":")[0]
                # Leftovers of a variable this cannot resolve (gcc-${VER},
                # jdk-${X}-zulu) and line continuations are not real packages.
                if not token or "$" in token or token in ("\\", "-"):
                    continue
                if token.endswith("-") or "--" in token:
                    continue
                if token not in names:
                    missing[token].add(path)
    return missing


# A URL that interpolates ${PKG_NAME} silently follows the package when it is
# renamed. rocknix-splash fetched from github.com/ROCKNIX/${PKG_NAME}, which was
# correct until the package became portareos-splash and started pointing at a
# repository that does not exist. Nothing in the tree catches that: the recipe
# still parses, the dependency still resolves, and the build fails at download.
# Interpolating ${PKG_NAME} is normal and correct for the many packages whose
# name matches their upstream repository (zlib, openssl, meson). It is only
# wrong once we have renamed the package, because then the name no longer
# matches upstream and the URL quietly follows the new one.
INTERPOLATES = re.compile(r'PKG_(?:URL|SOURCE_NAME)="[^"]*\$\{PKG_NAME\}')
OUR_PREFIX = "portareos"


def renamed_into_foreign_urls(recipes):
    bad = []
    for path, text in recipes:
        m = re.search(r'^PKG_NAME="([^"]+)"', text, re.M)
        if not m or not m.group(1).startswith(OUR_PREFIX):
            continue
        if INTERPOLATES.search(text):
            bad.append(path)
    return bad


# ${PKG_BUILD} and ${PKG_SOURCE_DIR} point into somebody else's source tree, so
# our own name has no business appearing in a path under them. The rebrand
# rewrote three such paths and each one built clean and failed at install:
#
#   ${PKG_BUILD}/portareos/gpcal-python-3.13.tgz     upstream ships rocknix/
#   ${PKG_BUILD}/overlay_server*/portareos_dtbo.py   upstream ships rocknix_dtbo.py
#
# Our name is legitimate in an install path (${INSTALL}/...), which is ours, and
# in the toolchain triplet, which is why that has to be spelled ${TARGET_NAME}
# rather than written out.
#
# The exception is a recipe with no PKG_URL and no unpack() of its own: then
# scripts/unpack fills ${PKG_BUILD} from nothing but the package's sources/
# directory, so the tree is ours and so is whatever our Makefile names in it.
UPSTREAM_PATH = re.compile(r'\$\{(?:PKG_BUILD|PKG_SOURCE_DIR)\}\S*portareos', re.I)
HAS_URL = re.compile(r'^\s*PKG_URL="[^"\s][^"]*"', re.M)
HAS_UNPACK = re.compile(r'^\s*unpack\(\)', re.M)


def builds_from_own_sources(path, text):
    return (os.path.isdir(os.path.join(os.path.dirname(path), "sources"))
            and not HAS_URL.search(text) and not HAS_UNPACK.search(text))


def our_name_in_upstream_paths(recipes):
    bad = []
    for path, text in recipes:
        if builds_from_own_sources(path, text):
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if UPSTREAM_PATH.search(line):
                bad.append((path, n, line.strip()))
    return bad


def main():
    names, recipes = load()
    missing = dangling(names, recipes)
    foreign = renamed_into_foreign_urls(recipes)
    upstream = our_name_in_upstream_paths(recipes)
    print(f"checked {len(names)} packages across {len(recipes)} recipes")
    if upstream:
        print("\nOUR NAME IN A PATH INTO UPSTREAM SOURCE:")
        for path, n, line in upstream:
            print(f"  {path}:{n}")
            print(f"    {line}")
        print("  ${PKG_BUILD} is upstream's tree, not ours. Use the name upstream")
        print("  actually ships, or ${TARGET_NAME} if this is the build triplet.")
        return 1
    if foreign:
        print("\nRENAMED PACKAGE WHOSE SOURCE URL STILL INTERPOLATES ${PKG_NAME}:")
        for path in foreign:
            print(f"  {path}")
        print("  Spell the upstream repository name out, so renaming the package")
        print("  here does not change where its source is fetched from.")
        return 1
    if not missing:
        print("OK: every dependency resolves, variable-driven lists included")
        return 0
    print("\nDANGLING DEPENDENCIES:")
    for name in sorted(missing):
        for path in sorted(missing[name])[:3]:
            print(f"  {name:<28} <- {path}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
