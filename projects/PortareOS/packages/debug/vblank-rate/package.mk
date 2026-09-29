# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="vblank-rate"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/portare-ch/portareos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain Python3"
PKG_LONGDESC="Measure the panel's real refresh rate from the DRM vblank counter"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/vblank-rate ${INSTALL}/usr/bin
    chmod 0755 ${INSTALL}/usr/bin/vblank-rate
}
