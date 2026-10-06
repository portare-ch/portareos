# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="core-info"
PKG_VERSION="5a74858ab2f7a50cebb5a6330895bc38899531c0"
PKG_SHA256="8fbcbfb2ae5bbeaacafb385db464b1d8778cf6680e567ad8d4a5ff1345e61c86"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/libretro/libretro-core-info"
PKG_URL="https://github.com/libretro/libretro-core-info/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Mirror of libretro's core info files"
PKG_TOOLCHAIN="manual"

# Only the cores the image ships (virtual/emulators, LIBRETRO_CORES); the
# other three hundred files described cores that are not there.
PKG_CORE_INFO="dolphin fbneo flycast gambatte genesis_plus_gx mesen2 mgba \
               neocd parallel_n64 picodrive ppsspp scummvm snes9x \
               swanstation ymir"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  for core in ${PKG_CORE_INFO}; do
    cp -a ${PKG_BUILD}/${core}_libretro.info ${INSTALL}/usr/lib/libretro/
  done

  # RetroArch allows run-ahead and preemptive frames only for a core whose
  # info file says "deterministic"; SwanStation's was lowered to "basic" in
  # libretro-core-info de2472e (July 2024) without a stated reason. The core
  # serialises the whole machine, takes the cheap memory-state path when the
  # frontend says a load is for run-ahead, and its own run-ahead option
  # tells users to prefer the frontend's. An explicit <system>.runahead
  # on the PlayStation needs this.
  sed -i 's/^savestate_features = "basic"$/savestate_features = "deterministic"/' \
    ${INSTALL}/usr/lib/libretro/swanstation_libretro.info
  grep -q '^savestate_features = "deterministic"$' \
    ${INSTALL}/usr/lib/libretro/swanstation_libretro.info
}
