# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="bluetooth-agent"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/portare-ch/portareos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain systemd bluez"
PKG_LONGDESC="The bluez pairing agent and auto-connector, on sd-bus"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portareos-bluetooth-agent ${INSTALL}/usr/bin
}
