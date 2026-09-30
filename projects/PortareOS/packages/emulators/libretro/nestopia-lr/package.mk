# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="nestopia-lr"
PKG_VERSION="8f00f500912a847062de432e38765c7285483e62"
PKG_SHA256="82aa1624189dad4302abe5af6cc6eee3821f34be346430566b3cab2904ce171b"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/nestopia"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Nestopia UE - cycle-accurate NES / Famicom emulator, reporting the console's exact 60.0988 Hz"
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="-C libretro"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a libretro/nestopia_libretro.so ${INSTALL}/usr/lib/libretro
}
