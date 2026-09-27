# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="emulators"
PKG_LICENSE="GPLv2"
PKG_SITE="https://rocknix.org"
PKG_SECTION="emulation" # Do not change to virtual or makeinstall_target will not execute.
PKG_LONGDESC="Emulation metapackage."
PKG_TOOLCHAIN="manual"

# es_systems.cfg is generated from config/emulators/<system>.conf by
# add_es_system (distributions/PortareOS/config/functions), so those files are
# part of this recipe even though they live outside it. Without this an edit
# to one of them never changed this package's stamp, and an incremental build
# shipped the old es_systems.cfg.
PKG_NEED_UNPACK="${ROOT}/config/emulators"

PKG_EMUS=""

# retropie-shaders and the GLSL shader packs are gone: they are for the gl
# driver, and this image runs RetroArch on Vulkan, which takes slang only.
PKG_RETROARCH="core-info libretro-database retroarch retroarch-assets retroarch-joypads slang-shaders"

LIBRETRO_CORES=" beetle-saturn-lr fbneo-lr flycast-lr gambatte-lr genesis-plus-gx-lr mgba-lr neocd_lr nestopia-lr parallel-n64-lr picodrive-lr scummvm-lr snes9x-lr swanstation-lr"

if [ "${ARCH}" = "aarch64" ]; then
  LIBRETRO_CORES+=" ppsspp-lr"
  PKG_EMUS+=" portmaster"
fi

case "${DEVICE}" in
  RK3399)
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  RK3566|RK3576)
    LIBRETRO_CORES+=" dolphin-lr"
    ;;
  RK3588)
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  SM6115)
    PKG_EMUS+=" armsx2-sa"
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  SM8250)
    PKG_EMUS+=" xemu-sa steam armsx2-sa"
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  SM8550)
    PKG_EMUS+=" xemu-sa steam armsx2-sa"
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  SM8650|SM8750)
    PKG_EMUS+=" xemu-sa steam armsx2-sa"
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  S922X)
    PKG_EMUS+=" armsx2-sa"
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
    ;;
  AMD64)
    PKG_EMUS+=" xemu-sa armsx2-sa"
    LIBRETRO_CORES+=" bsnes-lr dolphin-lr"
esac

# Split building emulators into 2 stages, needed to fit the jobs into the 6 hour GH runner time limit.
case "${TARGET_TYPE}" in
  cores_only)
    PKG_DEPENDS_TARGET+=" ${LIBRETRO_CORES}"
    ;;
  emus_only)
    PKG_DEPENDS_TARGET+=" ${PKG_EMUS} ${PKG_RETROARCH}"
    ;;
  none)
    ;;
  *)
    PKG_DEPENDS_TARGET+=" ${PKG_EMUS} ${PKG_RETROARCH} ${LIBRETRO_CORES}"
    ;;
esac

install_script() {
  if [ ! -d "${INSTALL}/usr/config/modules" ]; then
    mkdir -p ${INSTALL}/usr/config/modules
  fi
  cp -rf ${PKG_DIR}/sources/"${1}" ${INSTALL}/usr/config/modules
  chmod 0755 ${INSTALL}/usr/config/modules/"${1}"
}

makeinstall_target() {

  clean_es_cache
  clean_doc_cache

  add_system_dir /storage/roms/bezels

  add_system_dir /storage/roms/bios

  add_system_dir /storage/roms/music

  add_system_dir /storage/roms/savestates

  add_system_dir /storage/roms/themes

  start_system_doc

  ### Arcade
  add_emu_core arcade retroarch fbneo true
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system arcade

  ## Atari 800

  ## Atari ST

  ## Sammy Atomiswave
  add_emu_core atomiswave retroarch flycast true
  add_es_system atomiswave

  ### Sega Dreamcast
  add_emu_core dreamcast retroarch flycast true
  add_es_system dreamcast

  ### Nintendo GameBoy
  add_emu_core gb retroarch gambatte true
  case ${DEVICE} in
    RK3399|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      ;;
  esac
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gb

  ### Nintendo GameBoy Hacks
  add_emu_core gbh retroarch gambatte true
  case ${DEVICE} in
    RK3399|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      ;;
  esac
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gbh

  ### Nintendo GameBoy Advance
  add_emu_core gba retroarch mgba true
  case ${DEVICE} in
    H700|RK3326|RK3576|RK3566|S922X)
      ;;
    RK3399|RK3588|SM6115|SM8250|SM8550)
      ;;
    SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gba

  ### Nintendo GameBoy Advance Hacks
  add_emu_core gbah retroarch mgba true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550)
      ;;
    SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gbah

  ### Nintendo GameBoy Advance Video
  add_emu_core gbav retroarch mgba true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550)
      ;;
    SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gbav

  ### Nintendo GameBoy Color
  add_emu_core gbc retroarch gambatte true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gbc

  ### Nintendo GameBoy Color Hacks
  add_emu_core gbch retroarch gambatte true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gbch

  case ${DEVICE} in
    RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      add_emu_core gamecube retroarch dolphin true
      add_es_system gamecube
      ;;
  esac

  case ${DEVICE} in
    RK3399|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      add_emu_core triforce retroarch dolphin true
      add_es_system triforce
      ;;
  esac

  case ${DEVICE} in
    RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      add_emu_core wii retroarch dolphin true
      add_emu_core wiiware retroarch dolphin true
      add_es_system wii
      add_es_system wiiware
      ;;
  esac

  ### Sega GameGear
  add_emu_core gamegear retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system gamegear

  ### Sega GameGear Hacks
  add_emu_core ggh retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system ggh

  ## Steam & Heroic Games Launcher
  case ${DEVICE} in
    SM8250|SM8550|SM8650|SM8750)
      add_emu_core steam steam steam true
      install_script "Install Steam.sh"
      install_script "Uninstall Steam.sh"
      add_es_system steam
      ;;
  esac

  ### Sega MegaDrive
  add_emu_core megadrive-japan retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system megadrive-japan

  ### Nintendo MSU-1
  add_emu_core snesmsu1 retroarch snes9x true
  add_es_system snesmsu1

  ### Sega Naomi
  add_emu_core naomi retroarch flycast true
  add_es_system naomi

  ### SNK NeoGeo
  add_emu_core neogeo retroarch fbneo true
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac

  add_es_system neogeo

  ### SNK NeoCD
  add_emu_core neocd retroarch neocd true
  add_es_system neocd

  ### Nintendo NES, Famicom, Famicom Disk System
  add_emu_core nes retroarch nestopia true
  add_es_system nes
  add_emu_core famicom retroarch nestopia true
  add_es_system famicom
  add_emu_core fds retroarch nestopia true
  add_es_system fds

  ### Nintendo 64
  add_emu_core n64 retroarch parallel_n64 true
  add_es_system n64

  ### Nintendo 64 Disk Drive
  add_emu_core n64dd retroarch parallel_n64 true
  add_es_system n64dd

  ### Sony Playstation
  add_emu_core psx retroarch swanstation true
  add_es_system psx

  # The RK boards carried aethersx2 and nothing else, so they lose PS2 with it.
  case ${DEVICE} in
  AMD64|S922X|SM6115|SM8250|SM8550|SM8650|SM8750)
    add_emu_core ps2 armsx2 armsx2-sa true
    install_script "Start ARMSX2.sh"
    add_es_system ps2
    ;;
  esac

  ### Sony Playstation Portable
  add_emu_core psp retroarch ppsspp true
  add_es_system psp

  ### Sony Playstation Portable Minis
  add_emu_core pspminis retroarch ppsspp true
  add_es_system pspminis

  ### ScummVM
  add_emu_core scummvm retroarch scummvm true
  add_es_system scummvm
  add_system_dir /storage/roms/scummvm
  install_script "Start ScummVM.sh"

  ### Sega Saturn
  add_emu_core saturn retroarch mednafen_saturn true
  add_es_system saturn

  ### Sega 32X
  add_emu_core sega32x retroarch picodrive true
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system sega32x

  ### Sega CD
  add_emu_core segacd retroarch genesis_plus_gx true
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system segacd

  ### Sega Mega-CD
  add_emu_core megacd retroarch genesis_plus_gx true
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system megacd

  ### Sega Genesis
  add_emu_core genesis retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system genesis

  ### Sega Genesis Hacks
  add_emu_core genh retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system genh

  ### Sega MasterSystem
  add_emu_core mastersystem retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system mastersystem

  ### Sega MegaDrive
  add_emu_core megadrive retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system megadrive

  ### Sega MegaDrive Hacks
  add_emu_core megadriveh retroarch genesis_plus_gx true
  case ${DEVICE} in
    H700|RK3326|RK3399|RK3576|RK3566|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system megadriveh

  ### Sega SG-1000
  add_emu_core sg-1000 retroarch genesis_plus_gx true
  case ${DEVICE} in
    SM8550|SM8650|SM8750|AMD64)
      ;;
  esac
  add_es_system sg-1000

  case ${DEVICE} in
    SM8250|SM8550|SM8650|SM8750|AMD64)
      add_emu_core xbox xemu xemu-sa true
      add_es_system xbox
      install_script "Start Xemu.sh"
      ;;
  esac

  ### Nintendo SNES
  add_emu_core snes retroarch snes9x true
  case ${DEVICE} in
    RK3399|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      add_emu_core snes retroarch bsnes false
      ;;
  esac
  add_es_system snes

  ### Nintendo SNES Hacks
  add_emu_core snesh retroarch snes9x true
  case ${DEVICE} in
    RK3399|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      add_emu_core snesh retroarch bsnes false
      ;;
  esac
  add_es_system snesh

  ### Nintendo Super Famicom
  add_emu_core sfc retroarch snes9x true
  case ${DEVICE} in
    RK3399|RK3588|SM6115|SM8250|SM8550|SM8650|SM8750|S922X|AMD64)
      add_emu_core sfc retroarch bsnes false
      ;;
  esac
  add_es_system sfc

  ### Nintendo Stellaview
  add_emu_core satellaview retroarch snes9x true
  add_es_system satellaview

  ### Bandai SuFami Turbo
  add_emu_core sufami retroarch snes9x true
  add_es_system sufami

  ### PC Ports
  add_emu_core ports portmaster portmaster true
  add_es_system ports


  ### Movies. One player, mpv, on the panel's 119.88 Hz mode - see
  ### start_mpv.sh. RetroArch's built-in ffmpeg player used to cover this.
  add_emu_core movies mpv mpv true
  add_es_system movies

  ### Music Player
  add_emu_core music gmu gmu true
  add_es_system music

  ### Tools
  add_es_system tools

  ### Screenshots
  add_es_system imageviewer

  mk_es_systems

  mk_system_doc

  mkdir -p ${INSTALL}/usr/config/emulationstation
  cp -f ${ESTMP}/es_systems.cfg ${INSTALL}/usr/config/emulationstation

  if [ "${WINDOWMANAGER}" = "swaywm-env" ]; then
    sed -i 's~%RUNCOMMAND%~/usr/bin/foot %ROM%~g' ${INSTALL}/usr/config/emulationstation/es_systems.cfg
  else
    sed -i 's~%RUNCOMMAND%~/usr/bin/run %ROM%~g' ${INSTALL}/usr/config/emulationstation/es_systems.cfg
  fi

  cp -f ${ESTMP}/system-dirs.conf ${INSTALL}/usr/config

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/scripts/mkcontroller ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp ${PKG_DIR}/autostart/* ${INSTALL}/usr/lib/autostart/common
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/*
}
