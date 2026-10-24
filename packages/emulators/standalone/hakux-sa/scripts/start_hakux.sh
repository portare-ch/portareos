#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
#
# hakuX for an Xbox disc image (XISO).

. /etc/profile

# Home + Start quits hakuX itself; this is the launcher's kill, should it hang.
set_kill set "-9 hakux"

GAME=$(echo "${1}" | sed "s#^/.*/##")
PLATFORM=$(echo "${2}" | sed "s#^/.*/##")
ASPECT=$(get_setting aspect_ratio "${PLATFORM}" "${GAME}")
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")

case "${CORES}" in
  little) EMUPERF="${SLOW_CORES}" ;;
  big) EMUPERF="${FAST_CORES}" ;;
  *) unset EMUPERF ;;
esac

# 0 is 4:3, 1 is 16:9, otherwise the title's own.
case "${ASPECT}" in
  0) OPTIONS="aspect=4:3" ;;
  1) OPTIONS="aspect=16:9" ;;
  *) OPTIONS="aspect=auto" ;;
esac

# The emulated hard disk (the titles' saves) and the renderer's caches.
DATA="/storage/.config/hakux"
mkdir -p "${DATA}"

echo "Launching /usr/bin/hakux ${1} ${DATA} ${OPTIONS}"
${EMUPERF} /usr/bin/hakux "${1}" "${DATA}" ${OPTIONS}
