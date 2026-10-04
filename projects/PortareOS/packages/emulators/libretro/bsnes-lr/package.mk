# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="bsnes-lr"
PKG_VERSION="05439f96121d2b9d7ad7a5fc1f29d7eebdcc8c43"
PKG_SHA256="c32b646544eae0ec2fd467f32ee9b05d0b19d9af4fc8df9c73fa43f1f915812f"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/libretro/bsnes-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="bsnes - cycle-accurate Super Nintendo emulator, at the console's exact 60.0988 Hz and its DSP's 32040 Hz"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a bsnes_libretro.so ${INSTALL}/usr/lib/libretro
}
