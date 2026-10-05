#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

steam_ensure_fex_config_template() {
  if [ ! -d "/storage/.config/fex-emu" ]; then
    cp -r "/usr/config/fex-emu" "/storage/.config/"
  fi
}

steam_prepare_storage_and_vdf() {
  mkdir -p /storage/roms/steam/steamapps
  local vdf="/storage/.local/share/Steam/steamapps/libraryfolders.vdf"
  if [ -f "$vdf" ]; then
    grep -q '"/storage/roms/steam"' "$vdf" || sed -i '$ s/}/\t"1" {"path" "\/storage\/roms\/steam"}\n}/' "$vdf"
  fi
}

steam_load_es_thunk_settings() {
  GAME=$(echo "${1}" | sed "s#^/.*/##")
  PLATFORM=$(echo "${2}" | sed "s#^/.*/##")
  LSFG_ENABLE=$(get_setting lsfg_enable "${PLATFORM}" "${GAME}")
  LSFG_ENABLE=${LSFG_ENABLE:-0}
  LSFG_MULTIPLIER=$(get_setting lsfg_multiplier "${PLATFORM}" "${GAME}")
  LSFG_MULTIPLIER=${LSFG_MULTIPLIER:-2}
  LSFG_FLOW_SCALE=$(get_setting lsfg_flow_scale "${PLATFORM}" "${GAME}")
  LSFG_FLOW_SCALE=${LSFG_FLOW_SCALE:-0.30}
  LSFG_PERFORMANCE_MODE=$(get_setting lsfg_performance_mode "${PLATFORM}" "${GAME}")
  LSFG_PERFORMANCE_MODE=${LSFG_PERFORMANCE_MODE:-1}
  FPS_LIMIT=$(get_setting fps_limit "${PLATFORM}" "${GAME}")
  FPS_LIMIT=${FPS_LIMIT:-0}
  UI_SCALE=$(get_setting ui_scale "${PLATFORM}" "${GAME}")
  UI_SCALE=${UI_SCALE:-1.6}
}

# Big Picture takes its UI scale from Steam's own setting for the display,
# the one behind the slider under Settings > Display, saved in config.vdf
# under the display's name. Its automatic value is about 1.0 for the
# display gamescope fakes, and 1.0 is the Steam Deck's layout at the
# panel's 1280 pixels: on 91 mm that is text 1.7 times smaller than on a
# Deck. Steam rewrites every other scale key at start. Seed the saved
# entry once, when Steam has none for the display; the slider owns it
# afterwards.
# The diagonal, in inches, of the display gamescope fakes: four times the
# panel's 4.5. Steam names the display by it, and files the saved scale
# under that name.
STEAM_FAKE_DIAGONAL=18

steam_seed_ui_scale() {
  local cfg="/storage/.local/share/Steam/config/config.vdf"
  local name="External: gamescope ${STEAM_FAKE_DIAGONAL}\\\"|||Windowed"
  local tab entry line
  tab=$(printf '\t')
  [ -f "${cfg}" ] || return 0
  # The same string is a value in Steam's "Current" block; the saved entry
  # is the line that is only the key. grep reads no \t, hence the variable.
  grep -q "^[[:space:]]*\"External: gamescope ${STEAM_FAKE_DIAGONAL}[\\\\]\"|||Windowed\"\$" "${cfg}" && return 0
  entry=$(mktemp /tmp/steam-ui-scale.XXXXXX)
  if line=$(grep -n "^${tab}${tab}\"display\"\$" "${cfg}" | head -1 | cut -d: -f1) && [ -n "${line}" ]; then
    printf '\t\t\t"%s"\n\t\t\t{\n\t\t\t\t"ScaleFactor"\t\t"%s"\n\t\t\t}\n' "${name}" "${UI_SCALE}" >"${entry}"
  elif line=$(grep -n "^${tab}\"UI\"\$" "${cfg}" | head -1 | cut -d: -f1) && [ -n "${line}" ]; then
    printf '\t\t"display"\n\t\t{\n\t\t\t"%s"\n\t\t\t{\n\t\t\t\t"ScaleFactor"\t\t"%s"\n\t\t\t}\n\t\t}\n' "${name}" "${UI_SCALE}" >"${entry}"
  else
    line=$(( $(wc -l <"${cfg}") - 2 ))
    printf '\t"UI"\n\t{\n\t\t"display"\n\t\t{\n\t\t\t"%s"\n\t\t\t{\n\t\t\t\t"ScaleFactor"\t\t"%s"\n\t\t\t}\n\t\t}\n\t}\n' "${name}" "${UI_SCALE}" >"${entry}"
  fi
  # after the "{" that follows the key, or before the file's closing brace
  sed -i "$((line + 1))r ${entry}" "${cfg}"
  rm -f "${entry}"
}

steam_apply_fps_limit() {
  if [ "${FPS_LIMIT}" != "0" ]; then
    export DXVK_CONFIG="dxgi.maxFrameRate = ${FPS_LIMIT}"
    export VKD3D_FRAME_RATE=${FPS_LIMIT}
  fi
}

steam_apply_lsfg_settings() {
  if [ "${LSFG_ENABLE}" = "1" ]; then
    unset DISABLE_LSFGVK
    export LSFGVK_ENV=1
    export LSFGVK_DLL_PATH="/storage/.local/share/Steam/steamapps/common/Lossless Scaling/Lossless.dll"
    export LSFGVK_MULTIPLIER="${LSFG_MULTIPLIER}"
    export LSFGVK_FLOW_SCALE="${LSFG_FLOW_SCALE}"
    export LSFGVK_PERFORMANCE_MODE="${LSFG_PERFORMANCE_MODE}"
    export ENABLE_GAMESCOPE_WSI=0
  else
    export DISABLE_LSFGVK=1
  fi
}

steam_set_cpu_affinity() {
  local cores
  cores=$(get_setting "cores" "${PLATFORM}" "${GAME}")
  if [ "${cores}" = "little" ]; then
    EMUPERF="${SLOW_CORES}"
  elif [ "${cores}" = "big" ]; then
    EMUPERF="${FAST_CORES}"
  else
    unset EMUPERF
  fi
}

steam_debug_print() {
  echo "GAME set to: ${GAME}"
  echo "PLATFORM set to: ${PLATFORM}"
  echo "CPU CORES set to: ${EMUPERF}"
  echo "LSFG ENABLE set to: ${LSFG_ENABLE}"
  echo "LSFG MULTIPLIER set to: ${LSFG_MULTIPLIER}"
  echo "LSFG FLOW SCALE set to: ${LSFG_FLOW_SCALE}"
  echo "LSFG PERFORMANCE MODE set to: ${LSFG_PERFORMANCE_MODE}"
  echo "LSFG FPS LIMIT set to: ${FPS_LIMIT}"
  echo "VSYNC set to: ${VSYNC}"
}

# Asks DRM directly rather than asking a compositor. modetest is a query and
# needs no DRM master, so this works with the panel already handed over.
#
# The preferred mode's size and rounded rate, 1280x960 and 120. Several modes
# round to 120; gamescope (its patch 0007) takes the one whose exact rate is
# closest to what -r asks for, which is the panel's 120.000 Hz mode, there
# for Steam: timer-paced PC games make 60.000 frames a second, and at the
# preferred 119.88 gamescope would drop one of them about every 17 seconds.
steam_read_panel_geometry() {
  eval "$(/usr/bin/modetest -M msm -c 2>/dev/null | awk '
    /^[[:space:]]*#[0-9]+[[:space:]]/ && /preferred/ {
      split($2, wh, "x")
      printf "W=%s H=%s REFRESH_HZ=%d\n", wh[1], wh[2], $3 + 0.5
      exit
    }')"
  TRANSFORM="${TRANSFORM:-normal}"
  if [ -z "${W}" ] || [ -z "${H}" ] || [ -z "${REFRESH_HZ}" ]; then
    echo "start_steam: could not read the panel mode from modetest" >&2
    return 1
  fi
  # The physical size gamescope reports, in place of the panel's 91x68 mm.
  # Steam treats a display this small as built in: the Deck's fixed layout
  # and no scaling slider. A monitor-sized display is external, with the
  # slider and the brightness and FPS controls.
  # Upstream's 508x286 was a 16:9 23-inch; on a 4:3 panel that claims
  # pixels 1.33 times wider than tall, 64 dpi across and 85 down, for
  # anything that reads DPI per axis. Take the panel's shape at
  # STEAM_FAKE_DIAGONAL: 366x274 at 1280x960. The size is not how the UI
  # is scaled: Steam's automatic scale barely moves with it, 1.0 at 23
  # inches and 1.13 at 10 (steam_seed_ui_scale is).
  FAKE_MM=$(awk -v w="${W}" -v h="${H}" -v d="${STEAM_FAKE_DIAGONAL}" \
    'BEGIN { s = d * 25.4 / sqrt(w * w + h * h); printf "%dx%d", w * s + 0.5, h * s + 0.5 }')
}

steam_setup_environment() {
  TZ=$(timedatectl status | grep 'Time zone' | awk '{print $3}')
  [ -n "${TZ}" ] && export TZ
}

steam_touch_calibration_begin() {
  local orientation="$1"
  local model=""
  local name_path

  STEAM_TOUCH_EVENT=""
  STEAM_TOUCH_RULE=""

  [ "${orientation}" = "upsidedown" ] || return 0
  if [ -r /proc/device-tree/model ]; then
    model=$(tr -d '\000' </proc/device-tree/model)
  fi
  [ "${model}" = "AYANEO Pocket S Mini" ] || return 0

  for name_path in /sys/class/input/event*/device/name; do
    if [ "$(cat "${name_path}" 2>/dev/null)" = "Hynitron CST66xx Touchscreen" ]; then
      STEAM_TOUCH_EVENT="${name_path%/device/name}"
      break
    fi
  done
  [ -n "${STEAM_TOUCH_EVENT}" ] || return 0

  STEAM_TOUCH_RULE="/run/udev/rules.d/99-steam-touch-calibration.rules"
  mkdir -p "${STEAM_TOUCH_RULE%/*}"
  printf '%s\n' \
    'ACTION!="remove", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Hynitron CST66xx Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"' \
    >"${STEAM_TOUCH_RULE}"
  udevadm control --reload
  udevadm trigger --action=change "${STEAM_TOUCH_EVENT}"
  udevadm settle --timeout=3 >/dev/null 2>&1 || true
}

steam_touch_calibration_end() {
  [ -n "${STEAM_TOUCH_RULE:-}" ] || return 0

  rm -f "${STEAM_TOUCH_RULE}"
  udevadm control --reload >/dev/null 2>&1 || true
  if [ -n "${STEAM_TOUCH_EVENT:-}" ]; then
    udevadm trigger --action=change "${STEAM_TOUCH_EVENT}" \
      >/dev/null 2>&1 || true
  fi
  STEAM_TOUCH_RULE=""
  STEAM_TOUCH_EVENT=""
}

# runemu starts this in a scope in game.slice with the game's cpuset, and
# puts system.slice on the little cores for the duration
# (documentation/CPU_ISOLATION.md). A re-exec into system.slice landed
# there, where taskset -c 3-7 is refused and gamescope never started. Stay
# in the slice and the cpuset this was started in.
steam_scope_reexec_if_needed() {
  if [ -z "$_STEAM_SCOPE" ]; then
    local cgroup slice cpus
    cgroup=$(awk -F: '/^0::/ { print $3 }' /proc/self/cgroup)
    slice=${cgroup#/}; slice=${slice%%/*}
    case "${slice}" in *.slice) ;; *) slice="system.slice" ;; esac
    cpus=$(cat "/sys/fs/cgroup${cgroup}/cpuset.cpus.effective" 2>/dev/null)
    systemctl stop steam-bigpicture.scope 2>/dev/null || true
    exec systemd-run \
      --scope \
      --slice="${slice}" \
      ${cpus:+-p AllowedCPUs="${cpus}"} \
      --unit=steam-bigpicture \
      --collect \
      -E _STEAM_SCOPE=1 \
      -E HOME="$HOME" \
      -E USER="$USER" \
      -E TZ="$TZ" \
      -- "${STEAM_MAIN_SCRIPT}" "$@"
  fi
}

steam_dual_screen_begin() {
  if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
    swaymsg 'seat seat1 fallback true'
    PREFER_OUTPUT="--prefer-output $SDL_VIDEO_DISPLAY_PRIORITY"
  fi
}

steam_dual_screen_end() {
  if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
    swaymsg 'seat seat1 fallback false'
  fi
}

# The arm64 client links against libraries this image does not ship, libpulse
# above all: pulse is banned here and the ban stays, since pipewire-pulse is
# what answers Steam. Steam's own arm64 runtime carries them, but under their
# versioned file names only, so nothing resolves a plain soname and steamui.so
# dies with "Failed to load steamui.so".
#
# Link the sonames the client asks for into the directory the launch already
# puts on LD_LIBRARY_PATH. Only what the image is missing, because that path
# comes first and a link for a library we do ship would shadow it. libpulse
# pulls in libpulsecommon and libasyncns, neither of which is a soname the
# client names itself.
steam_arm64_link_runtime_libs() {
  local libdir="/storage/.local/share/Steam/lib/aarch64-linux-gnu"
  local runtime
  runtime=$(ls -d /storage/.local/share/Steam/steam-runtime-steamrt-arm64/*/files/lib/aarch64-linux-gnu 2>/dev/null | sort | tail -1)

  [ -d "${runtime}" ] || return 0
  mkdir -p "${libdir}"

  local soname src
  for soname in libpulse.so.0 libasyncns.so.0 libva.so.2 libibus-1.0.so.5; do
    [ -e "/usr/lib/${soname}" ] && continue
    src=$(ls "${runtime}/${soname}"* 2>/dev/null | sort | tail -1)
    [ -n "${src}" ] && ln -sfn "${src}" "${libdir}/${soname}"
  done

  # Named for the pulseaudio release rather than an ABI, so it is linked under
  # whatever name the runtime ships and follows a runtime update by itself.
  for src in "${runtime}"/pulseaudio/libpulsecommon-*.so; do
    [ -e "${src}" ] && ln -sfn "${src}" "${libdir}/$(basename "${src}")"
  done

  # And whatever else the client's own binaries name that neither the image
  # nor the links so far provide, asked of ldd until nothing new resolves:
  # the image drops what nothing of its own uses, and Valve's client moves.
  # On 20260925 that was GTK2 with ATK, AT-SPI and gdk-pixbuf, CUPS and the
  # Kerberos libraries behind it. A few old FFmpeg sonames stay unresolved;
  # the client runs without them.
  local bins missing linked pass
  bins=$(find /storage/.local/share/Steam/steamrtarm64 \
              /storage/.local/share/Steam/linuxarm64 -maxdepth 1 -type f \
              \( -name '*.so' -o -name steam -o -name steamwebhelper \) 2>/dev/null)
  [ -n "${bins}" ] || return 0
  for pass in 1 2 3 4 5 6 7 8; do
    missing=$(for src in ${bins}; do LD_LIBRARY_PATH="${libdir}" ldd "${src}" 2>/dev/null; done |
              awk '/=> not found/ { print $1 }' | sort -u)
    linked=""
    for soname in ${missing}; do
      src=$(ls "${runtime}/${soname}"* 2>/dev/null | sort | tail -1)
      [ -n "${src}" ] && ln -sfn "${src}" "${libdir}/${soname}" && linked=1
    done
    [ -n "${linked}" ] || break
  done
}

# The box86 and box64 handlers this used to switch off are not on the image;
# FEX's own FEX-x86 and FEX-x86_64 stay registered.
steam_arm64_binfmt_and_proton_prep() {
  rm -f "/storage/.local/share/Steam/compatibilitytools.d/compatibilitytool.vdf"
}

steam_launch_bigpicture() {
  local game_uri=""
  local force_orientation="normal"
  local gamescope_mode_file="/storage/.config/gamescope/modes.cfg"
  local steam_exit_code=0
  local gamescope_exit_code=0
  local steam_exit_code_file=""
  if [ "${TRANSFORM}" = "90" ]; then
    force_orientation="right"
  elif [ "${TRANSFORM}" = "180" ]; then
    force_orientation="upsidedown"
  elif [ "${TRANSFORM}" = "270" ]; then
    force_orientation="left"
  fi

  if [[ "$1" == *.desktop && -f "$1" && "$(basename "$1")" != "Steam.desktop" ]]; then
    local exec_line
    exec_line=$(grep -m1 '^Exec=' "$1" | cut -d'=' -f2-)
    game_uri="${exec_line#steam } -silent"
  fi

  mkdir -p "$(dirname "$gamescope_mode_file")"
  touch "$gamescope_mode_file"
  if [ "${STEAM_FLAVOR}" = "arm64" ]; then
    export STEAM_COMPAT_GRAPHICS_PROVIDER=//storage/.local/share/fex-emu/RootFS/ArchLinux/graphics_provider.json
    steam_exit_code_file=$(mktemp /tmp/steam-exit-code.XXXXXX)
    # Nothing to stop: portarelauncher drops DRM master before running
    # this, and gamescope takes it. Nothing to start afterwards either -
    # the front-end never left.
    steam_touch_calibration_begin "${force_orientation}"
    trap steam_touch_calibration_end EXIT
    while true; do
      rm -f "${steam_exit_code_file}"
      GAMESCOPE_MODE_SAVE_FILE="${gamescope_mode_file}" GAMESCOPE_FAKE_OUTPUT_MM="${FAKE_MM}" \
      env -u WAYLAND_DISPLAY LD_LIBRARY_PATH=/storage/.local/share/Steam/lib/aarch64-linux-gnu/ ${EMUPERF} \
      gamescope $PREFER_OUTPUT -W "$W" -H "$H" -r "$REFRESH_HZ" --xwayland-count 2 --mangoapp --backend drm --force-orientation "${force_orientation}" -e -- \
      /bin/bash -c '
        exit_file="$1"
        shift
        "$@"
        printf "%s\n" "$?" >"${exit_file}"
      ' _ "${steam_exit_code_file}" \
      /storage/.local/share/Steam/steamrtarm64/steam -deckard -steamos3 -gamepadui -noshaders ${game_uri:+"$game_uri"}
      gamescope_exit_code=$?
      if [ -f "${steam_exit_code_file}" ]; then
        steam_exit_code=$(cat "${steam_exit_code_file}")
      else
        steam_exit_code=${gamescope_exit_code}
      fi
      [ "${steam_exit_code}" = "42" ] || break
    done
    rm -f "${steam_exit_code_file}"
    steam_touch_calibration_end
    trap - EXIT
    exit 0
  else
    FEX /usr/bin/steam -exitsteam
    # Nothing to stop: portarelauncher drops DRM master before running
    # this, and gamescope takes it. Nothing to start afterwards either -
    # the front-end never left.
    steam_touch_calibration_begin "${force_orientation}"
    trap steam_touch_calibration_end EXIT
    GAMESCOPE_MODE_SAVE_FILE="${gamescope_mode_file}" GAMESCOPE_FAKE_OUTPUT_MM="${FAKE_MM}" env -u WAYLAND_DISPLAY ${EMUPERF} \
      gamescope $PREFER_OUTPUT -W "$W" -H "$H" -r "$REFRESH_HZ" --xwayland-count 2 --backend drm --force-orientation "${force_orientation}" -- \
      FEX /usr/bin/steam -nobigpicture -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders ${game_uri:+"$game_uri"}
    steam_touch_calibration_end
    trap - EXIT
    exit 0
  fi
}

# Entry point from EmulationStation (not used when this file is sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source /etc/profile
  GAME=$(echo "${1}" | sed "s#^/.*/##")
  PLATFORM=$(echo "${2}" | sed "s#^/.*/##")
  STEAM_VERSION=$(get_setting steam_version "${PLATFORM}" "${GAME}")
  STEAM_VERSION=${STEAM_VERSION:-"arm64"}
  echo "STEAM_VERSION set to: ${STEAM_VERSION}"
  if [ "${STEAM_VERSION}" = "arm64" ]; then
    exec /usr/bin/start_steam_arm64.sh "$@"
  else
    exec /usr/bin/start_steam_x86.sh "$@"
  fi
fi
