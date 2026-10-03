# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="nestopia-lr"
PKG_VERSION="b9fdc9c4e6d374abacd1a678ae46ec7f963ef59a"
PKG_SHA256="5e5081b2fd5ad3ef83f9fa1bcd9d25b8b16bf0d9dfebc9a78ab0d014ffa62869"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/nestopia"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Nestopia UE - cycle-accurate NES / Famicom emulator, reporting the console's exact 60.0988 Hz"
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="-C libretro"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a libretro/nestopia_libretro.so ${INSTALL}/usr/lib/libretro
}
