# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="gambatte-lr"
PKG_VERSION="7809bb68ee96c3e6c74e9d9c4c8bb09aa7c6801d"
PKG_SHA256="874744cd0e5fc965fcd1b49e14d1b792505c8bb18937bf4611950c435b4420fb"
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
