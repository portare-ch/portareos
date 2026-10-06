# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="portarelauncher"
PKG_VERSION="0.5.0"
PKG_SHA256="d57fd1d0838f361d62f302ee8a56daf779e18a9708ccbac2364595731d6a04da"
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

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portarelauncher ${INSTALL}/usr/bin
}
