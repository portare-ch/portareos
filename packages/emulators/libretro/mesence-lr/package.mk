# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="mesence-lr"
PKG_VERSION="a449fdc19580b86edcfc2a4c84eeb5e99462225b"
PKG_SHA256="ed5e81c291d9738ede23b88b0526504fb21e0054e3eb10ca93d4fcac70dd2956"
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
