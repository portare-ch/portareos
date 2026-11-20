# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="mesence-lr"
PKG_VERSION="10a8ef2b8e55f0f0411085e83a2f0457c145cc78"
PKG_SHA256="de88381a4556f8fc96c691b972b44edd6bfcb05f331d805cebadf605684d313c"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/libretro/MesenCE"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="MesenCE - the NES emulator of the nesdev community's Mesen continuation, at the console's exact 60.0988 Hz"
PKG_TOOLCHAIN="make"

# STATICLINK=false: the Makefile links -static-libstdc++ on Linux, and the
# toolchain builds libstdc++ shared only (gcc --disable-static).
PKG_MAKE_OPTS_TARGET="-f Makefile.libretro platform=unix STATICLINK=false"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a mesen2_libretro.so ${INSTALL}/usr/lib/libretro
}
