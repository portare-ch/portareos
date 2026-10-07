# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="portarelauncher"
PKG_VERSION="0.7.0"
PKG_SHA256="c2544068f772647a5d814db99f90dd21b39d26eae7686a9e4462c86e1d2518a1"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/portare-ch/portarelauncher"
# A release, not a commit: the tarball is made once by the launcher's release
# workflow and published with its checksum. To bump, set PKG_VERSION to the
# release and PKG_SHA256 to the value in its .sha256 file.
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain libdrm portnet"
PKG_LONGDESC="The front-end: a KMS launcher that owns the panel directly."
PKG_TOOLCHAIN="make"

# libdrm and libc, and that is the whole list. No GBM, EGL, Vulkan or Mesa -
# a text screen on a black field is a dumb buffer and a memcpy, so the GPU
# never leaves idle while the menu is up.

# portscope is the input diagnostics the launcher opens from Settings >
# Diagnostics, at /usr/bin/portscope. ja26.bin is the kana and kanji the
# launcher draws in Japanese, read from /usr/share/portarelauncher; it is
# Noto Sans CJK, so its notice and the Open Font License go with it.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portarelauncher ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portscope ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/usr/share/portarelauncher
    cp -a ${PKG_BUILD}/data/ja26.bin ${PKG_BUILD}/data/ja26.NOTICE \
          ${PKG_BUILD}/data/OFL-1.1.txt ${INSTALL}/usr/share/portarelauncher
}
