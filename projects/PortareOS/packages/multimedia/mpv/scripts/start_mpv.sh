#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

# Movies. mpv is the only player on the device, and it draws straight to the
# panel through Vulkan's VK_KHR_display - no compositor, the same path
# RetroArch takes. portarelauncher has dropped DRM master by the time this runs.

. /etc/profile

set_kill set "mpv"

VK="--vo=gpu-next --gpu-api=vulkan --gpu-context=displayvk"

# The panel's 119.88 Hz mode, found by its rate rather than assumed to be the
# first. It is 120000/1001 exactly, so film at 24000/1001 is five refreshes
# per frame, 29.97 is four and 59.94 is two - every NTSC rate lands on a whole
# number of refreshes and nothing needs resampling. The panel also has a
# 119.63 Hz mode for PlayStation 240p; Vulkan lists only the preferred one
# today, and picking by rate keeps this right if that ever changes.
MODE=$(/usr/bin/mpv --no-config ${VK} --vulkan-display-mode=help 2>/dev/null |
       sed -n 's/^ *Mode \([0-9]\+\): .*(119\.880 Hz)$/\1/p' | head -n1)
if [ -z "${MODE}" ]; then
  log $0 "no 119.880 Hz mode listed, using the first"
  MODE=0
fi

mkdir -p /storage/.config/mpv/watch_later

# --no-config: what plays a film here is this file and input.conf, not
#   whatever an earlier mpv left in /storage.
# video-sync=audio: frames are timed against the audio clock and rendered
#   only when the picture changes - 24 times a second for film. The panel's
#   119.88 Hz is a whole multiple of every NTSC rate (5x 23.976, 4x 29.97,
#   2x 59.94), so there is nothing to resample. display-resample, used
#   before, rendered at every refresh instead: 120 times a second with the
#   SD scaler and scanlines, more than the GPU managed at its top clock -
#   The Wire dropped 2290 frames in its first 4.5 minutes, the display-sync
#   ratio read 2.75 where 5.00 was due, and A-V wandered up to 90 ms.
# decode.conf: the iris hardware decoder for H.264 and HEVC, read through
#   ffmpeg's demuxer - see that file for why and for the measurements.
# aspect.conf: standard-definition rips that lost their 4:3 flag are shown at
#   4:3, so they fill the panel instead of sitting between black bars.
# sd.conf: scanlines and a sharper scaler for standard definition; SELECT
#   turns the scanlines off.
# quit-watch-later on the back button, so a film resumes where it was left.
# save-position-on-quit for every other way out - above all Home + START,
#   where the launcher ends mpv with SIGTERM, which quits without saving
#   unless this is set.
exec /usr/bin/mpv --no-config \
  --script=/usr/config/mpv/seek-reinit.lua \
  ${VK} --vulkan-display-mode=$((10#${MODE})) \
  --video-sync=audio \
  --include=/usr/config/mpv/decode.conf \
  --include=/usr/config/mpv/aspect.conf \
  --include=/usr/config/mpv/sd.conf \
  --ao=pipewire \
  --input-gamepad=yes --input-conf=/usr/config/mpv/input.conf \
  --watch-later-dir=/storage/.config/mpv/watch_later \
  --save-position-on-quit \
  --sub-auto=fuzzy \
  "${1}"
