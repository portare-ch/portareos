# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="mesence-lr"
PKG_VERSION="10c91ddd0785f371f36c6e287a95ce8563ad6670"
PKG_SHA256="530300f32ed77cce9fc98702e07a77be2f6e1543590ba8d6ca034571d5af8e5d"
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
