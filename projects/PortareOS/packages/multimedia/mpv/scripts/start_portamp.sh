#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

# PORTAMP. Music, on the same mpv and the same Vulkan display path as the
# film player - a track has no picture, so the picture is a spectrum
# analyser and portamp.lua draws a Linamp face and the playlist around it
# on the OSD.
#
# This replaced gmu, which was a second audio stack (SDL2, mpg123, vorbis,
# flac, opus) for the one job mpv already does through ffmpeg. Nothing new
# is built for it: the analyser is libavfilter, the chrome is Lua and the
# gamepad is mpv's own.

. /etc/profile

set_kill set "mpv"

VK="--vo=gpu-next --gpu-api=vulkan --gpu-context=displayvk"

# The panel's 119.88 Hz mode, by rate rather than by index - the same
# reasoning as start_mpv.sh, and the analyser is rendered at 60 fps, which
# is a whole half of it.
MODE=$(/usr/bin/mpv --no-config ${VK} --vulkan-display-mode=help 2>/dev/null |
       sed -n 's/^ *Mode \([0-9]\+\): .*(119\.880 Hz)$/\1/p' | head -n1)
if [ -z "${MODE}" ]; then
  log $0 "no 119.880 Hz mode listed, using the first"
  MODE=0
fi

# The analyser graph is a file of its own: it carries a weighting curve full
# of quotes and parentheses, and passing that through the shell as a string
# mangles it.
VIS="$(cat /usr/config/mpv/portamp-filter.txt)"

# A track opens its folder as the playlist, starting from that track, and
# a folder picked in the launcher plays whole; directory-mode=ignore keeps
# it to that folder's own files. It plays once and PORTAMP returns to the
# launcher, as the film player does - looping restarted a single track
# forever. force-window because there is no video track to open a window.
# osd-level 0: portamp.lua owns the screen and draws the time itself.
exec /usr/bin/mpv --no-config \
  ${VK} --vulkan-display-mode=$((10#${MODE})) \
  --force-window=yes \
  --autocreate-playlist=filter --directory-filter-types=audio --directory-mode=ignore \
  --keep-open=no \
  --lavfi-complex="${VIS}" \
  --video-unscaled=yes \
  --script=/usr/config/mpv/portamp.lua \
  --ao=pipewire \
  --input-gamepad=yes --input-conf=/usr/config/mpv/portamp-input.conf \
  --osd-level=0 \
  "${1}"
