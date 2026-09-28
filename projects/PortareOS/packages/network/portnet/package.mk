# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="portnet"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/portare-ch/portareos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain systemd iwd"
PKG_LONGDESC="Wi-Fi through iwd, on sd-bus, in place of nmcli"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/portnet ${INSTALL}/usr/bin
    cp -a ${PKG_DIR}/scripts/portnet-migrate ${INSTALL}/usr/bin
    chmod 0755 ${INSTALL}/usr/bin/portnet-migrate
}
