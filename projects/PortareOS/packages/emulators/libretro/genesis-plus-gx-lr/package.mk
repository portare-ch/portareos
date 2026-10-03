# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="genesis-plus-gx-lr"
PKG_VERSION="58c341487e5bfcf979ea68413c7987633adb0c56"
PKG_SHA256="5081fa17b4fe9fbf8fb3228f94e87381eaac364c8776486b821e41ac379fd4e1"
PKG_LICENSE="Non-commercial"
PKG_SITE="https://github.com/libretro/Genesis-Plus-GX"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="An enhanced port of Genesis Plus for Gamecube/Wii"
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="-f Makefile.libretro"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a genesis_plus_gx_libretro.so ${INSTALL}/usr/lib/libretro/genesis_plus_gx_libretro.so
}
