# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="scummvm-lr"
PKG_VERSION="fcbce3ae815269dacdc309092bc92ccc6d3e13bb"
PKG_SHA256="7e60fec38740f90bb987c79d8f8623faa48485373907d3a15a13b0b3b353a316"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/scummvm"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain soundfont-generaluser"
PKG_LONGDESC="ScummVM as a libretro core: the adventure engines, with their MIDI synth built in"
PKG_TOOLCHAIN="make"

# The core's Makefile fetches libretro-deps and libretro-common itself, at
# the commits it names, and builds what it needs from them: zlib, png,
# freetype, vorbis, FluidLite and the rest are compiled in. No fluidsynth
# on the image, then: the synth is FluidLite inside the core, per game,
# and the soundfont it plays is the one the shipped scummvm.ini names.
# `all` builds the core and scummvm.zip, the data files and themes of
# this exact version, which have to travel with it.
#
# LITE=1 builds only the engines in lite_engines.list, and the list is
# ours (config/engines.list): the engines the standalone shipped, as its
# release build chose them, with each one's default sub-engines named as
# well, since the list does not imply them, less ten that are no use on
# a handheld: glk, ultima and mm want a keyboard (text adventures, the
# Ultima and Might and Magic RPGs); director, bagel, mtropolis-class
# multimedia CD-ROMs and the one-title engines crab, ngi, hypno, gamos
# and plumbers carry nothing anyone will play here. Every engine in the
# tree came to 120 MB, the standalone's set to 99, this to 77.
# FORCE_OPENGLNONE=1 is the standalone's --opengl-mode=none: no GL
# renderer in the core, so it never asks RetroArch for a GL context and
# RetroArch stays on Vulkan, where the timed presents are.
#
# The tree has a configure script at its root (ScummVM's own, unused
# here), so the build system runs make from an out-of-tree directory
# under ${PKG_BUILD}, where a relative -C path finds nothing. Hence the
# absolute path, in a function: ${PKG_BUILD} is not set yet when this
# file is read.
pre_make_target() {
  cp ${PKG_DIR}/config/engines.list ${PKG_BUILD}/backends/platform/libretro/lite_engines.list
}

make_target() {
  make -C ${PKG_BUILD}/backends/platform/libretro platform=unix LITE=1 FORCE_OPENGLNONE=1 all
}

makeinstall_target() {
  local LR="${PKG_BUILD}/backends/platform/libretro"
  mkdir -p ${INSTALL}/usr/lib/libretro
    cp -a "${LR}/scummvm_libretro.so" ${INSTALL}/usr/lib/libretro

  # The bundle unpacks to scummvm/theme and scummvm/extra, the layout the
  # core looks for under RetroArch's system directory. post-update copies
  # it there (/storage/roms/bios/scummvm) after every update, so the data
  # always matches the core.
  mkdir -p ${INSTALL}/usr/share
    unzip -qo "${LR}/scummvm.zip" -d ${INSTALL}/usr/share

  # The ini the core starts from, once, next to that: post-update puts it
  # in place only when there is none, since it is where added games live.
  mkdir -p ${INSTALL}/usr/config/scummvm
    cp -a ${PKG_DIR}/config/scummvm.ini ${INSTALL}/usr/config/scummvm
}
