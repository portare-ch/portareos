# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="present-probe"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/portare-ch/portareos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain vulkan-headers vulkan-loader"
PKG_LONGDESC="Present a known schedule through Vulkan's KHR display path and log what the driver reports"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/present-probe ${INSTALL}/usr/bin
}
