#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Source predefined functions and variables
. /etc/profile
. /etc/os-release

### Switch to performance mode early to speed up configuration and reduce time it takes to get into games.
performance

# Command line schema
# $1 = Game/Port
# $2 = Platform
# $3 = Core
# $4 = Emulator

ARGUMENTS="$@"
PLATFORM="${ARGUMENTS##*-P}"  # read from -P onwards
PLATFORM="${PLATFORM%% *}"  # until a space is found
CORE="${ARGUMENTS##*--core=}"  # read from --core= onwards
CORE="${CORE%% *}"  # until a space is found
EMULATOR="${ARGUMENTS##*--emulator=}"  # read from --emulator= onwards
EMULATOR="${EMULATOR%% *}"  # until a space is found
ROMNAME="$1"
BASEROMNAME=${ROMNAME##*/}
GAMEFOLDER="${ROMNAME//${BASEROMNAME}}"

### A KMS launch hands the panel to the emulator itself, which page flips
### straight to the display with no compositor to composite and blit
### through. Nothing has to be stopped for that any more: portarelauncher
### holds DRM master, drops it before exec'ing this script, and takes it
### back when this script returns.
KMSMODE=$(get_setting "kmsmode" "${PLATFORM}" "${BASEROMNAME}")

### RetroArch runs on KMS unless something says otherwise. It was built
### with --enable-kms, it page flips straight to the panel, and under a
### compositor it is a wayland client whose frame callbacks are not a
### vblank lock. The setting is still read first, so a platform or a
### single game can still turn it off; this only supplies the default
### that was previously missing, which left the whole KMS path built,
### wired and never once taken.
###
### Keyed on the emulator rather than the platform: the standalone
### emulators have their own display handling and several of them do
### want a compositor.
###
### ArmSX2 joins it: its SDL frontend has no window at all and takes the
### panel through VK_KHR_display, whatever the renderer setting says - see
### start_armsx2.sh.
case "${EMULATOR}" in
  retroarch|armsx2)
    [ -z "${KMSMODE}" ] && KMSMODE=1
    ;;
esac

### start_armsx2.sh needs to know which display path it is on.
export KMSMODE

### This used to re-exec into a scope of its own, because taking the
### display meant stopping the front-end, and stopping the front-end killed
### everything in its cgroup including this script. portarelauncher does not
### go away: it drops DRM master, runs this, and takes master back when it
### exits. So there is nothing to survive and nothing to re-exec into.

### One emulator at a time.
###
### Nothing stopped a second launch while the first was still up. An
### emulator that wedges rather than exits - which Dolphin does here -
### leaves this script in wait() forever, the front-end comes back, and
### the next launch starts a whole second emulator on top of the first.
### Three were found running at once, each holding its own address space
### and its own GPU context, which is enough by itself to make Dolphin's
### mprotect fail and to put two renderers on one panel.
###
### The pid file is the record rather than a pgrep pattern, because every
### wrapper the front-end puts around this script carries "runemu.sh" in
### its command line, this one included, and a pattern wide enough to
### find the old run is wide enough to kill the new one.
RUNEMU_PID_FILE="/tmp/.runemu.pid"

kill_tree() {
  local pid="${1}" sig="${2}" child
  for child in $(pgrep -P "${pid}" 2>/dev/null); do
    kill_tree "${child}" "${sig}"
  done
  kill "-${sig}" "${pid}" 2>/dev/null
}

reap_previous_run() {
  local previous
  [ -f "${RUNEMU_PID_FILE}" ] || return 0
  previous="$(cat "${RUNEMU_PID_FILE}" 2>/dev/null)"
  rm -f "${RUNEMU_PID_FILE}"
  case "${previous}" in ''|*[!0-9]*) return 0 ;; esac
  [ "${previous}" = "$$" ] && return 0
  [ -d "/proc/${previous}" ] || return 0
  grep -q "runemu" "/proc/${previous}/cmdline" 2>/dev/null || return 0

  log $0 "A previous run (${previous}) is still up, taking it down"
  ### TERM first: a healthy emulator writes its saves on the way out.
  kill_tree "${previous}" TERM
  local waited=0
  while [ -d "/proc/${previous}" ] && [ "${waited}" -lt 5 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if [ -d "/proc/${previous}" ]; then
    log $0 "Previous run ignored TERM, killing"
    kill_tree "${previous}" KILL
    sleep 1
  fi
}

### Define the variables used throughout the script
BLUETOOTH_STATE=$(get_setting controllers.bluetooth.enabled)
ES_CONFIG="/storage/.emulationstation/es_settings.cfg"
VERBOSE=false
LOG_DIRECTORY="/var/log"
LOG_FILE="exec.log"
RUN_SHELL="/usr/bin/bash"
RETROARCH_TEMP_CONFIG="/storage/.config/retroarch/retroarch.cfg"
RETROARCH_APPEND_CONFIG="/tmp/.retroarch.cfg"
NETWORK_PLAY="No"
SET_SETTINGS_TMP="/tmp/shader"
OUTPUT_LOG="${LOG_DIRECTORY}/${LOG_FILE}"
SCRIPT_NAME=$(basename "$0")

### Function Library
function log() {
        if [ ${LOG} == true ]
        then
                if [[ ! -d "$LOG_DIRECTORY" ]]
                then
                        mkdir -p "$LOG_DIRECTORY"
                fi
                echo "${SCRIPT_NAME}: $*" 2>&1 | tee -a ${LOG_DIRECTORY}/${LOG_FILE}
        else
                echo "${SCRIPT_NAME}: $*"
        fi
}

function loginit() {
        if [ ${LOG} == true ]
        then
                if [ -e ${LOG_DIRECTORY}/${LOG_FILE} ]
                then
                        rm -f ${LOG_DIRECTORY}/${LOG_FILE}
                fi
                cat <<EOF >${LOG_DIRECTORY}/${LOG_FILE}
Emulation Run Log - Started at $(date)

ARG1: $1
ARG2: $2
ARG3: $3
ARG4: $4
ARGS: $*
EMULATOR: ${EMULATOR}
PLATFORM: ${PLATFORM}
CORE: ${CORE}
ROM NAME: ${ROMNAME}
BASE ROM NAME: ${ROMNAME##*/}
USING CONFIG: ${RETROARCH_TEMP_CONFIG}
USING APPENDCONFIG : ${RETROARCH_APPEND_CONFIG}

EOF
        else
                log $0 "Emulation Run Log - Started at $(date)"
        fi
}

function quit() {
        ${VERBOSE} && log $0 "Cleaning up and exiting"
        rm -f "${RUNEMU_PID_FILE}" 2>/dev/null
        bluetooth enable
        set_kill set "emulationstation"
        clear_screen
        DEVICE_CPU_GOVERNOR=$(get_setting system.cpugovernor)
        ${DEVICE_CPU_GOVERNOR}
        exit $1
}

function clear_screen() {
        ${VERBOSE} && log $0 "Clearing screen"
        clear
}

function bluetooth() {
        if [ "$1" == "disable" ]
        then
                ${VERBOSE} && log $0 "Disabling BT"
                if [[ "${BLUETOOTH_STATE}" == "1" ]]
                then
                        NPID=$(pgrep -f portareos-bluetooth-agent)
                        if [[ ! -z "$NPID" ]]; then
                                kill "$NPID"
                        fi
                fi
        elif [ "$1" == "enable" ]
        then
                ${VERBOSE} && log $0 "Enabling BT"
                if [[ "${BLUETOOTH_STATE}" == "1" ]]
                then
                        systemd-run portareos-bluetooth-agent
                fi
        fi
}

### Enable logging
case $(get_setting system.loglevel) in
  off|none)
    LOG=false
  ;;
  verbose)
    LOG=true
    VERBOSE=true
  ;;
  *)
    LOG=true
  ;;
esac

### Prepare to load our emulator and game.
loginit "$1" "$2" "$3" "$4"

### Take down anything still running from a previous launch before this
### one starts. Placed here rather than at the top because it logs, and
### log() is not defined until loginit has run.
reap_previous_run
echo "$$" >"${RUNEMU_PID_FILE}"

clear_screen
bluetooth disable
set_kill stop

### Determine which emulator we're launching and make appropriate adjustments before launching.
${VERBOSE} && log $0 "Configuring for ${EMULATOR}"
case ${EMULATOR} in
  mednafen)
    set_kill set "-9 mednafen"
    RUNTHIS='${RUN_SHELL} /usr/bin/start_mednafen.sh "${ROMNAME}" "${CORE}" "${PLATFORM}"'
  ;;
  retroarch)
    # Make sure NETWORK_PLAY isn't defined before we start our tests/configuration.
    del_setting netplay.mode

    case ${ARGUMENTS} in
      *"--host"*)
        ${VERBOSE} && log $0 "Setup netplay host."
        NETWORK_PLAY="${ARGUMENTS##*--host}"  # read from --host onwards
        NETWORK_PLAY="${NETWORK_PLAY%%--nick*}"  # until --nick is found
        NETWORK_PLAY="--host ${NETWORK_PLAY} --nick"
        set_setting netplay.mode "host"
      ;;
      *"--connect"*)
        ${VERBOSE} && log $0 "Setup netplay client."
        NETWORK_PLAY="${ARGUMENTS##*--connect}"  # read from --connect onwards
        NETWORK_PLAY="${NETWORK_PLAY%%--nick*}"  # until --nick is found
        NETWORK_PLAY="--connect ${NETWORK_PLAY} --nick"
        set_setting netplay.mode "client"
      ;;
      *"--netplaymode spectator"*)
        ${VERBOSE} && log $0 "Setup netplay spectator."
        set_setting "netplay.mode" "spectator"
      ;;
    esac

    ### Set set_kill to kill the appropriate retroarch
    set_kill set "retroarch"

    RABIN="retroarch"


    ### Configure specific emulator requirements
    case ${CORE} in
      easyrpg*)
        # easyrpg needs runtime files to be downloaded on the first run
        ${VERBOSE} && log $0 "Setup easyrpg requirements."
        /usr/bin/easyrpg.sh
      ;;
    esac


    RUNTHIS='${EMUPERF} /usr/bin/${RABIN} -L /tmp/cores/${CORE}_libretro.so --config ${RETROARCH_TEMP_CONFIG} --appendconfig ${RETROARCH_APPEND_CONFIG} "${ROMNAME}"'

    CONTROLLERCONFIG="${ARGUMENTS#*--controllers=*}"

    if [[ "${ARGUMENTS}" == *"-state_slot"* ]]
    then
      CONTROLLERCONFIG="${CONTROLLERCONFIG%% -state_slot*}"  # until -state is found
      SNAPSHOT="${ARGUMENTS#*-state_slot *}" # -state_slot x
      SNAPSHOT="${SNAPSHOT%% -*}"
        if [[ "${ARGUMENTS}" == *"-autosave"* ]]; then
          CONTROLLERCONFIG="${CONTROLLERCONFIG%% -autosave*}"  # until -autosave is found
          AUTOSAVE="${ARGUMENTS#*-autosave *}" # -autosave x
          AUTOSAVE="${AUTOSAVE%% -*}"
        else
          AUTOSAVE=""
        fi
    else
      CONTROLLERCONFIG="${CONTROLLERCONFIG%% --*}"  # until a -- is found
      SNAPSHOT=""
      AUTOSAVE=""
    fi

    # Configure platform specific requirements
    case ${PLATFORM} in
      "atomiswave")
        rm ${ROMNAME}.nvmem*
      ;;
    esac

    ### Configure retroarch
    if [ -e "${SET_SETTINGS_TMP}" ]
    then
      rm -f "${SET_SETTINGS_TMP}"
    fi
    ${VERBOSE} && log $0 "Execute setsettings (${PLATFORM} ${ROMNAME} ${CORE} --controllers=${CONTROLLERCONFIG} --autosave=${AUTOSAVE} --snapshot=${SNAPSHOT})"
    (/usr/bin/setsettings.sh "${PLATFORM}" "${ROMNAME}" "${CORE}" --controllers="${CONTROLLERCONFIG}" --autosave="${AUTOSAVE}" --snapshot="${SNAPSHOT}" >${SET_SETTINGS_TMP})

    ### Enable RetroArch Network Control for this session on dual-screen devices
    ### so the bottom-screen UI can forward save-state / load-state / resume commands.
    if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
      echo 'network_cmd_enable = "true"' >> "${RETROARCH_APPEND_CONFIG}"
      echo 'network_cmd_port = "55355"'  >> "${RETROARCH_APPEND_CONFIG}"
      echo 'savestate_thumbnail_enable = "true"' >> "${RETROARCH_APPEND_CONFIG}"
      echo 'cheevos_custom_host = "http://127.0.0.1:4874"' >> "${RETROARCH_APPEND_CONFIG}"

      if ! pgrep -f 'python3 .*/lowerdeck/ra_proxy\.py' >/dev/null 2>&1; then
        ( python3 /usr/share/lowerdeck/ra_proxy.py >/dev/null 2>&1 ) &
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          netstat -ln 2>/dev/null | grep -q ':4874 ' && break
          sleep 0.1
        done
      fi
    fi

    ### If setsettings wrote data in the background, grab it and assign it to EXTRAOPTS
    if [ -e "${SET_SETTINGS_TMP}" ]
    then
      EXTRAOPTS=$(cat ${SET_SETTINGS_TMP})
      rm -f ${SET_SETTINGS_TMP}
      ${VERBOSE} && log $0 "Extra Options: ${EXTRAOPTS}"
    fi

    if [[ ${EXTRAOPTS} != 0 ]]; then
      RUNTHIS=$(echo ${RUNTHIS} | sed "s|--config|${EXTRAOPTS} --config|")
    fi
  ;;
  *)
    case ${PLATFORM} in
      "setup")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      "gamecube"|"triforce")
        RUNTHIS='${RUN_SHELL} /usr/bin/start_dolphin_gc.sh "${ROMNAME}" "${PLATFORM}" "${CORE}"'
      ;;
      "wii"|"wiiware")
        RUNTHIS='${RUN_SHELL} /usr/bin/start_dolphin_wii.sh "${ROMNAME}" "${PLATFORM}" "${CORE}"'
      ;;
      "ports")
      if [[ "${ROMNAME,,}" == *".appimage" ]]; then
        RUNTHIS='${EMUPERF} "${ROMNAME}"'
      else
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
      fi
        chmod +x "${ROMNAME}"
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "windows")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        # Hook into Portmaster control mapping
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "shell")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      *)
        RUNTHIS='${RUN_SHELL} "/usr/bin/start_${CORE%-*}.sh" "${ROMNAME}" "${PLATFORM}"'
      ;;
    esac
  ;;
esac

### Execution time.
clear_screen
${VERBOSE} && log $0 "executing game: ${ROMNAME}"
${VERBOSE} && log $0 "script to execute: ${RUNTHIS}"

### Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${ROMNAME##*/}")
${VERBOSE} && log $0 "Configure big.little (${CORES})"
case ${CORES} in
  little)
    EMUPERF="${SLOW_CORES}"
  ;;
  big)
    EMUPERF="${FAST_CORES}"
  ;;
  *)
    unset EMUPERF
  ;;
esac

### We need the original system cooling profile later so get it now!
COOLINGPROFILE=$(get_setting cooling.profile)

### Configure GPU performance mode
GPUPERF=$(get_setting "gpuperf" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z ${GPUPERF} ]
then
  ${VERBOSE} && log $0 "Set GPU performance to (${GPUPERF})"
  gpu_performance_level ${GPUPERF}
  get_gpu_performance_level >/tmp/.gpu_performance_level
fi

if [ "${DEVICE_HAS_FAN}" = "true" ]
then
  ### Set any custom fan profile (make this better!)
  GAMEFAN=$(get_setting "cooling.profile" "${PLATFORM}" "${ROMNAME##*/}")
  if [ ! -z "${GAMEFAN}" ]
  then
    ${VERBOSE} && log $0 "Set fan profile to (${GAMEFAN})"
    set_setting cooling.profile ${GAMEFAN}
    systemctl restart fancontrol
  fi
fi

### Display mode for emulation
DISPLAY_MODE=$(get_setting "display_mode" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${DISPLAY_MODE}" ] && [ "${DISPLAY_MODE}" != "default" ]
then
  set_refresh_rate "${DISPLAY_MODE}"
fi

FORCEPACK=$(get_setting "forcepack" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${FORCEPACK}" ] && [ "${FORCEPACK}" = "On" ]
then
    ${VERBOSE} && log $0 "Enabling panfrost forcepack"
    export PAN_MESA_DEBUG=forcepack
fi

### Offline all but the number of threads we need for this game if configured.
NUMTHREADS=$(get_setting "threads" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${NUMTHREADS}" ] &&
   [ ! ${NUMTHREADS} = "default" ]
then
  ${VERBOSE} && log $0 "Configure active cores (${NUMTHREADS})"
  onlinethreads ${NUMTHREADS} 0
fi

### Set the governor mode for emulation
CPU_GOVERNOR=$(get_setting "cpugovernor" "${PLATFORM}" "${ROMNAME##*/}")
${VERBOSE} && log $0 "Set emulation performance mode to (${CPU_GOVERNOR})"
${CPU_GOVERNOR}

### Check whether MangoHud is supported and enabled
if [ "${DEVICE_MANGOHUD_SUPPORT}" == "true" ]; then
  MANGOHUD_ENABLED=$(get_setting "portareos.mangohud.enabled"  "${PLATFORM}" "${ROMNAME##*/}")
  if [ "${MANGOHUD_ENABLED}" = "1" ]; then
    # Enable GPU profiling and MangoHud
    gpu_profiling "on"
    RUNTHIS="/usr/bin/mangohud ${RUNTHIS}"
    ${VERBOSE} && log $0 "Enabling MangoHud"
  fi
fi

### Take the display for a KMS launch. SDL finds the panel through GBM,
### but only while nothing else holds DRM master - and by the time this
### runs, nothing does. portarelauncher calls drmDropMaster() before it
### execs this script, so there is no compositor to stop and no wait for
### one to let go.
if [ "${KMSMODE}" = "1" ]; then
  ${VERBOSE} && log $0 "KMS launch, display already handed over"
  export SDL_VIDEODRIVER=kmsdrm
  export SDL_KMSDRM_REQUIRE_DRM_MASTER=1
  unset WAYLAND_DISPLAY DISPLAY

  ### RetroArch does not go through SDL for the display. It was built
  ### with --enable-kms and picks that context on its own once nothing
  ### hands it a wayland socket, but the config carries a context
  ### setting of its own, so name it rather than hope.
  if [ -n "${RABIN}" ]; then
    echo 'video_context_driver = "kms"' >> "${RETROARCH_APPEND_CONFIG}"
  fi
fi

# If the rom is a shell script just execute it, useful for DOSBOX and ScummVM scan scripts
if [[ "${ROMNAME}" == *".sh" ]] && [ ! "${PLATFORM}" = "ports" ] && [ ! "${PLATFORM}" = "windows" ]; then
        ${VERBOSE} && log $0 "Executing shell script ${ROMNAME}"
        "${ROMNAME}" &>>${OUTPUT_LOG}
        ret_error=$?
else
        ${VERBOSE} && log $0 "Executing $(eval echo ${RUNTHIS})"
        eval ${RUNTHIS} &>>${OUTPUT_LOG}
        ret_error=$?
fi

### Switch back to performance mode to clean up
performance

clear_screen

### Disable touch on the secondary screen for dual screen devices
if [[ "${DEVICE_HAS_DUAL_SCREEN}" == "true" ]]; then
  # Disable touch events for Retroid Pocket devices to prevent focus loss
  if [[ "${QUIRK_DEVICE}" == "Retroid Pocket 5" || "${QUIRK_DEVICE}" == "Retroid Pocket Flip2" || "${QUIRK_DEVICE}" == "Retroid Pocket Mini" || "${QUIRK_DEVICE}" == "Retroid Pocket Mini V2" ]]; then
    swaymsg input "0:0:generic_ft5x06_(a0)" events disabled
    swaymsg input "0:0:generic_ft5x06_(8d)" events disabled
  fi
fi

### Go back to system display mode , if we had specialized mode defined
DISPLAY_MODE=$(get_setting "display_mode" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${DISPLAY_MODE}" ] && [ "${DISPLAY_MODE}" != "default" ]
then
  DISPLAY_MODE=$(get_setting "system.display_mode")
  DISPLAY_OUTPUT=$(/usr/bin/wlr-randr | awk 'NR==1{print $1;}')
  if [ -z "${DISPLAY_MODE}" ]; then
    # if we have no system mode use the displays preferred mode
    /usr/bin/wlr-randr --output ${DISPLAY_OUTPUT} --preferred
  else
    # If we have user specifed system mode set that
    set_refresh_rate "${DISPLAY_MODE}"
  fi
fi

### Restore cooling profile.
if [ "${DEVICE_HAS_FAN}" = "true" ]
then
  ${VERBOSE} && log $0 "Restore system cooling profile (${COOLINGPROFILE})"
  set_setting cooling.profile ${COOLINGPROFILE}
  systemctl restart fancontrol &
fi

### Restore system GPU performance mode
GPUPERF=$(get_setting "system.gpuperf")
if [ ! -z ${GPUPERF} ]
then
  ${VERBOSE} && log $0 "Restore system GPU performance mode (${GPUPERF})"
  gpu_performance_level ${GPUPERF} &
else
  ${VERBOSE} && log $0 "Restore system GPU performance mode (auto)"
  gpu_performance_level auto &
fi
rm -f /tmp/.gpu_performance_level 2>/dev/null

### Reset the number of cores to use.
NUMTHREADS=$(get_setting "system.threads")
${VERBOSE} && log $0 "Restore active threads (${NUMTHREADS})"
if [ -n "${NUMTHREADS}" ]
then
        onlinethreads ${NUMTHREADS} 0 &
else
        onlinethreads all 1 &
fi

### Disable GPU profiling
gpu_profiling "off"

### No cloud backup of saves after a game: rclone went with EmulationStation,
### whose menus configured it. The call it made went through /usr/bin/run,
### which stops ${UI_SERVICE} first - with the launcher as the UI service,
### cloud.backup=1 would have taken the front-end down after every game.

### Nothing to bring back. The front-end never left - it is the parent of
### this script and takes DRM master again when this returns.

${VERBOSE} && log $0 "Checking errors: ${ret_error} "
if [ "${ret_error}" == "0" ]
then
        quit 0
else
        log $0 "exiting with ${ret_error}"
        quit 1
fi
