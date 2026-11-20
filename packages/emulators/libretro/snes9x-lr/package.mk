# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="snes9x-lr"
PKG_VERSION="204ea1c0b851f960cbf223075eb1c25641cb483c"
PKG_SHA256="506b07a775401f9357258fdae0fb0638a6e0f82093657d294aa51c046dcee67c"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/libretro/snes9x"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Snes9x - Portable Super Nintendo Entertainment System (TM) emulator"
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="-C libretro"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a libretro/snes9x_libretro.so ${INSTALL}/usr/lib/libretro
}
