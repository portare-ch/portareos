# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="tear-test"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/portare-ch/portareos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain libdrm"
PKG_LONGDESC="Count torn frames from the DPU's per-frame CRC"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/tear-test ${INSTALL}/usr/bin
}
