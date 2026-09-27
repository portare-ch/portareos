# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ROCKNIX (https://github.com/ROCKNIX)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="sdl3text"
PKG_VERSION="v1.0"
PKG_LICENSE="GPLv2"
PKG_SITE="https://rocknix.org"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain SDL3 SDL3_ttf dejavu"
PKG_LONGDESC="SDL3 text reader with gamepad controls; RetroArch shows game guides with it"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -a ${PKG_BUILD}/sdl3text ${INSTALL}/usr/bin
}
