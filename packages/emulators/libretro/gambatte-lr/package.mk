# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="gambatte-lr"
PKG_VERSION="138bcbbf311300a271896bf93a76370c72cab339"
PKG_SHA256="01810705ababe48a22fc190039eff5d9785f74ebf7fbd08b0c10d2312c55e99b"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/libretro/gambatte-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libretro implementation of libgambatte"

PKG_MAKE_OPTS_TARGET="-f Makefile.libretro"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a gambatte_libretro.so ${INSTALL}/usr/lib/libretro
}
