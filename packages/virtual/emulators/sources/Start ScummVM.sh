#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

source /etc/profile

# ScummVM's own launcher, in RetroArch with the core and no game: where a
# game is added, and where Tools > Playlist Generator writes the .scummvm
# hook file into the game's folder under /storage/roms/scummvm, which is
# what the consoles list shows.

set_kill set "retroarch"

/usr/bin/retroarch -L /tmp/cores/scummvm_libretro.so \
  --config /storage/.config/retroarch/retroarch.cfg >/dev/null 2>&1
