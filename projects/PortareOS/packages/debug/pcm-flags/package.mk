# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="pcm-flags"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/portare-ch/portareos"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain alsa-lib"
PKG_LONGDESC="Read a PCM's info flags and period steps from the driver"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/pcm-flags ${INSTALL}/usr/bin
}
