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

  # Disc games are CHD only (config/emulators/{neocd,psx,ps2,dreamcast,
  # saturn,segacd,megacd}.conf, the README's note): lossless, smaller, and
  # nova-push converts before it copies. An .m3u names CHDs for a multi-disc game. The info files say
  # the same so RetroArch's own content filter matches the launcher's.
  sed -i 's/^supported_extensions = "cue|chd"$/supported_extensions = "chd"/' \
    ${INSTALL}/usr/lib/libretro/neocd_libretro.info
  grep -q '^supported_extensions = "chd"$' \
    ${INSTALL}/usr/lib/libretro/neocd_libretro.info
  sed -i 's/^supported_extensions = "exe|psexe|cue|bin|img|iso|chd|pbp|ecm|mds|psf|m3u"$/supported_extensions = "chd|m3u"/' \
    ${INSTALL}/usr/lib/libretro/swanstation_libretro.info
  grep -q '^supported_extensions = "chd|m3u"$' \
    ${INSTALL}/usr/lib/libretro/swanstation_libretro.info
  sed -i 's/^supported_extensions = "cue|chd|mds|ccd|iso|m3u"$/supported_extensions = "chd|m3u"/' \
    ${INSTALL}/usr/lib/libretro/ymir_libretro.info
  grep -q '^supported_extensions = "chd|m3u"$' \
    ${INSTALL}/usr/lib/libretro/ymir_libretro.info
  # PSP is CHD, or PBP for homebrew and PSN titles, which have no disc.
  sed -i 's/^supported_extensions = "elf|iso|cso|prx|pbp|chd"$/supported_extensions = "chd|pbp"/' \
    ${INSTALL}/usr/lib/libretro/ppsspp_libretro.info
  grep -q '^supported_extensions = "chd|pbp"$' \
    ${INSTALL}/usr/lib/libretro/ppsspp_libretro.info
  # ARMSX2's info file ships with the core (armsx2-lr does the same there).
  # Flycast's file is left alone: the same core runs Naomi and Atomiswave
  # from .zip and .lst, so its list cannot be CHD only; dreamcast.conf is.
  # Genesis Plus GX's likewise: it runs the cartridge systems too, and
  # segacd.conf and megacd.conf carry the rule.
  # GameCube and Wii discs are RVZ, Dolphin's lossless format, rather than
  # CHD: it regenerates the discs' pseudo-random padding and keeps Wii data
  # decrypted, which CHD cannot compress. .dol homebrew and .wad channels
  # have no disc; Dolphin's FIFO logs (.dff) and .tgc go.
  sed -i 's/^supported_extensions = "gcm|iso|wbfs|ciso|gcz|elf|dol|dff|tgc|wad|rvz|m3u|wia"$/supported_extensions = "rvz|dol|wad|m3u"/' \
    ${INSTALL}/usr/lib/libretro/dolphin_libretro.info
  grep -q '^supported_extensions = "rvz|dol|wad|m3u"$' \
    ${INSTALL}/usr/lib/libretro/dolphin_libretro.info

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

  # NeoCD's file predates the savestate keys (display_version 2019) and
  # says nothing about them, which RetroArch and gamecapture read as no
  # savestates at all. The core serialises the whole machine and declares
  # its states deterministic (RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS,
  # none set), so say so; run-ahead, preemptive frames and captures gate
  # on this.
  sed -i '/^supports_no_game = "false"$/a savestate = "true"\nsavestate_features = "deterministic"' \
    ${INSTALL}/usr/lib/libretro/neocd_libretro.info
  grep -q '^savestate_features = "deterministic"$' \
    ${INSTALL}/usr/lib/libretro/neocd_libretro.info
}
