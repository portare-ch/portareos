# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="portarelauncher"
PKG_VERSION="0.9.1"
PKG_SHA256="96d02bfb190c0043367c4f3e5cc01dfe88b814ef6669e9eca46c1c72fe76c8a0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/portare-ch/portarelauncher"
# A release, not a commit: the tarball is made once by the launcher's release
# workflow and published with its checksum. To bump, set PKG_VERSION to the
# release and PKG_SHA256 to the value in its .sha256 file.
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain cmake:host libdrm portnet"
PKG_LONGDESC="The front-end: a KMS launcher that owns the panel directly."
PKG_TOOLCHAIN="make"

# libdrm and libc, and that is the whole list. No GBM, EGL, Vulkan or Mesa -
# a text screen on a black field is a dumb buffer and a memcpy, so the GPU
# never leaves idle while the menu is up. The CHD decoder lives in ps-chd-id,
# the helper the launcher runs to name a PS1, PS2, PSP or Neo Geo CD disc
# image; it is built by the Makefile through CMake with the toolchain's
# $CMAKE, and links only the libchdr it vendors.

# The default target also regenerates the PlayStation title tables from the
# vendored PCSX2 index and libretro DATs, with Python and PyYAML. The tables
# are in the tarball, so build the three binaries and install them as shipped.
#
# The toolchain exports CMAKE as "cmake -DCMAKE_TOOLCHAIN_FILE=... -D...", and
# the Makefile runs "$(CMAKE) --build", which cmake refuses with -D options in
# front of it. So CMAKE is the bare program here and the toolchain file goes
# in through the Makefile's own PS_CMAKE_ARGS.
make_target() {
  make portarelauncher portscope ps-chd-id \
    CMAKE=cmake PS_CMAKE_ARGS="-DCMAKE_TOOLCHAIN_FILE=${CMAKE_CONF}"
}

# portscope is the input diagnostics the launcher opens from Settings >
# Diagnostics, at /usr/bin/portscope. ja26.bin is the kana and kanji the
# launcher draws in Japanese, read from /usr/share/portarelauncher; it is
# Noto Sans CJK, so its notice and the Open Font License go with it.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portarelauncher ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portscope ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/ps-chd-id ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/usr/share/portarelauncher
    cp -a ${PKG_BUILD}/data/ja26.bin ${PKG_BUILD}/data/ja26.NOTICE \
          ${PKG_BUILD}/data/OFL-1.1.txt ${INSTALL}/usr/share/portarelauncher
    # The offline title sources, and the notices of what they and the CHD
    # decoder are made from: the same files and names as the Makefile's
    # install-disc-titles, without its dependency on regenerating the tables.
    cp -a ${PKG_BUILD}/data/ps2-titles.tsv ${PKG_BUILD}/data/psx-titles.tsv \
          ${PKG_BUILD}/data/psp-titles.tsv ${PKG_BUILD}/data/neocd-titles.tsv \
          ${INSTALL}/usr/share/portarelauncher
  mkdir -p ${INSTALL}/usr/share/portarelauncher/notices
    cp -a ${PKG_BUILD}/third_party/libretro/NOTICE ${INSTALL}/usr/share/portarelauncher/notices/LIBRETRO-NOTICE.txt
    cp -a ${PKG_BUILD}/third_party/libretro/LICENSE ${INSTALL}/usr/share/portarelauncher/notices/LIBRETRO-LICENSE.txt
    cp -a ${PKG_BUILD}/third_party/CHD-NOTICES.txt ${INSTALL}/usr/share/portarelauncher/notices/CHD-NOTICES.txt
    cp -a ${PKG_BUILD}/third_party/pcsx2/NOTICE ${INSTALL}/usr/share/portarelauncher/notices/PCSX2-NOTICE.txt
    cp -a ${PKG_BUILD}/third_party/pcsx2/COPYING.GPLv3 ${INSTALL}/usr/share/portarelauncher/notices/PCSX2-COPYING.GPLv3
}
