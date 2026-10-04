# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="mesence-lr"
PKG_VERSION="4c4e069f16a8ad6ed79e046046c56d51558c7daf"
PKG_SHA256="5394ac20492b3b5a596ae8e8097b44669bd482932ccd031dc64783c9890cdb20"
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
