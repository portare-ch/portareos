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
# The socket is how power-handler finds a playing PORTAMP and hands it the
# power key, which then switches the screen instead of suspending.
# The analyser is a 360x100 video at portamp.lua's VIS, (64,212): the
# margins start the video area there and the alignment puts it in the
# corner. 64.4 and 212.4 pixels, so it lands on 64 and 212 whether mpv
# rounds or truncates - one off shows a line of black at the edge.
# portamp-rate is the select filter portamp.lua slows to a frame a second
# in the dark.
#
# Music is a light load, so it runs on the three little cores. FFmpeg
# sizes its filter threads from the CPUs it may use, and each filter in
# the analyser graph is held to one: at 360x100, splitting a frame across
# threads cost more than it saved. The built-in scripts are off; the
# playlist, the time and the controls are portamp.lua's. Together that
# took mpv from 51 threads to 19, all on the little cores.
exec ${SLOW_CORES} /usr/bin/mpv --no-config \
  --vf=@portamp-rate:lavfi=[select=1]:o=[threads=1] \
  ${VK} --vulkan-display-mode=$((10#${MODE})) \
  --force-window=yes \
  --autocreate-playlist=filter --directory-filter-types=audio --directory-mode=ignore \
  --keep-open=no \
  --lavfi-complex="${VIS}" \
  --video-unscaled=yes --video-align-x=-1 --video-align-y=-1 \
  --video-margin-ratio-left=0.0503125 --video-margin-ratio-top=0.22125 \
  --script=/usr/config/mpv/portamp.lua \
  --ao=pipewire \
  --input-gamepad=yes --input-conf=/usr/config/mpv/portamp-input.conf \
  --osd-level=0 --input-ipc-server=/run/portamp.sock \
  --osc=no --ytdl=no --load-stats-overlay=no --load-console=no \
  --load-select=no --load-positioning=no --load-context-menu=no \
  --load-commands=no --load-auto-profiles=no --input-terminal=no \
  "${1}"
