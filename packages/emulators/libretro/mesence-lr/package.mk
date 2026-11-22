# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="mesence-lr"
PKG_VERSION="1534e57f862d1a8cb1a719446af11108e2c4ae26"
PKG_SHA256="cd2dd5a347fc80e4b5103cd407efc2a66ac4dfc4afe01b00bf302f76d8a8eaa4"
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
