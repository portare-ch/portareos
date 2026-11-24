# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="genesis-plus-gx-lr"
PKG_VERSION="099c962e7374eb84cae9bba180c9e0e49e767b40"
PKG_SHA256="5146e86c16a0e7cf32206533434880f0b45cf294c0575a97ace7bda0e338d219"
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
