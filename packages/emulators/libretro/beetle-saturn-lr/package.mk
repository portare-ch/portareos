# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="beetle-saturn-lr"
PKG_VERSION="65f05fa66f83e65e33be83aa433d883b4fd9509a"
PKG_SHA256="aadede29d18eae53d4ed69886e17caf7d03ee533b5b1118d4e658c2ffb8a3272"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/beetle-saturn-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Beetle Saturn - Mednafen's Sega Saturn core, software rendered, with aarch64 JITs for the SCU and SCSP DSPs"
PKG_TOOLCHAIN="make"

# patches/001: report the exact NTSC rate, 28636363.63 / 478660 = 59.826105 Hz,
# instead of upstream's rounded 59.8265, so the 119.652237 Hz panel mode is a
# lock. Needs sega_101.bin and mpr-17933.bin in /storage/roms/bios.

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a mednafen_saturn_libretro.so ${INSTALL}/usr/lib/libretro
}
