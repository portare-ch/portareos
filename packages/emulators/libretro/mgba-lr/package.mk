# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="mgba-lr"
PKG_VERSION="7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6"
PKG_SHA256="5cbf639e527fb586bf33e14d59037eab35f78f45154e0b79c784fff474c3bc37"
PKG_LICENSE="MPL-2.0"
PKG_SITE="https://github.com/libretro/mgba"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="mGBA Game Boy Advance Emulator"

PKG_CMAKE_OPTS_TARGET="-DLIBMGBA_ONLY=ON -DBUILD_LIBRETRO=ON"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a mgba_libretro.so ${INSTALL}/usr/lib/libretro
}
