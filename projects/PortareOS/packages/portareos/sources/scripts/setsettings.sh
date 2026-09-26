#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

. /etc/profile

###
### System configuration variables
###

SYSTEM_CONFIG="/storage/.config/system/configs/system.cfg"
RETROARCH_PATH="/storage/.config/retroarch"
RETROARCH_CONFIG="${RETROARCH_PATH}/retroarch.cfg"
RETROARCH_TEMPLATE="/usr/config/retroarch/retroarch.cfg"

ROMS_DIR="/storage/roms"
SNAPSHOTS="${ROMS_DIR}/savestates"
BEZEL_DIR="/storage/roms/bezels"

TMP_CONFIG="/tmp/.retroarch.cfg"
LOG_DIR="/var/log"
LOG_FILE="exec.log"
LOCK_FILE="/tmp/.retroarch.lock"

###
### Variables parsed from the command line
###

PLATFORM=${1,,}
ROM="${2##*/}"
CORE=${3,,}

#Autosave
AUTOSAVE="$@"
AUTOSAVE="${AUTOSAVE#*-autosave=*}"
AUTOSAVE="${AUTOSAVE% --*}"

#Snapshot
SNAPSHOT="$@"
SNAPSHOT="${SNAPSHOT#*--snapshot=*}"

#Controllers
CONTROLLERS="$@"
CONTROLLERS="${CONTROLLERS#*--controllers=*}"

###
### Arrays containing various supported/non-supported attributes.
###

declare -a HAS_CHEEVOS=(    arcade
                            arduboy
                            atari2600
                            atari7800
                            atarilynx
                            cdi
                            colecovision
                            cps1
                            cps2
                            cps3
                            dreamcast
                            famicom
                            fbn
                            fds
                            gamegear
                            gb
                            gbh
                            gba
                            gbah
                            gbav
                            gbc
                            gbch
                            gbh
                            genesis
                            genh
                            ggh
                            intellivision
                            mastersystem
                            megacd
                            megadrive
                            megadrive-japan
                            msx
                            msx2
                            n64
                            nds
                            neogeo
                            neogeocd
                            nes
                            nesh
                            ngp
                            ngpc
                            odyssey2
                            3do
                            pcengine
                            pcenginecd
                            pcfx
                            pokemini
                            psp
                            psx
                            ps2
                            saturn
                            sega32x
                            segacd
                            sfc
                            sg-1000
                            snes
                            snesh
                            snesmsu1
                            supergrafx
                            supervision
                            tg16
                            tg16cd
                            vectrex
                            virtualboy
                            wonderswan
                            wonderswancolor
)

declare -a NO_REWIND=(  atomiswave
                        dreamcast
                        mame
                        n64
                        naomi
                        neogeocd
                        odyssey2
                        psp
                        pspminis
                        saturn
                        sega32x
                        zxspectrum
)

declare -a NO_RUNAHEAD=(    atomiswave
                            dreamcast
                            n64
                            naomi
                            neogeocd
                            psp
                            saturn
                            sega32x
)

declare -a NO_ANALOG=(  dreamcast
                        gc
                        n64
                        nds
                        ps2
                        psp
                        pspminis
                        psx
                        wii
                        wonderswan
                        wonderswancolor
)

declare -a CORE_RATIOS=(    4/3
                            16/9
                            16/10
                            16/15
                            21/9
                            1/1
                            2/1
                            3/2
                            3/4
                            4/1
                            9/16
                            5/4
                            6/5
                            7/9
                            8/3
                            8/7
                            19/12
                            19/14
                            30/17
                            32/9
                            config
                            squarepixel
                            core
                            custom
                            full
)

declare -a LANG_CODES=( ["false"]="0"
                        ["En"]="1"
                        ["Fr"]="3"
                        ["Pt"]="49"
                        ["De"]="5"
                        ["El"]="30"
                        ["Es"]="2"
                        ["Cs"]="8"
                        ["Da"]="9"
                        ["Hr"]="11"
                        ["Hu"]="35"
                        ["It"]="4"
                        ["Ja"]="6"
                        ["Ko"]="12"
                        ["Nl"]="7"
                        ["Nn"]="46"
                        ["Po"]="48"
                        ["Ro"]="50"
                        ["Ru"]="51"
                        ["Sv"]="10"
                        ["Tr"]="59"
                        ["Zh"]="13"
)

###
### Fetch common settings
###

LOGGING=$(get_setting system.loglevel)
if [ -z "${LOGGING}" ]
then
  LOGGING="none"
fi

###
### Set up
###

### Create log directory if it doesn't exist
if [ ! -d "${LOG_DIR}" ]
then
    mkdir -p ${LOG_DIR}
fi

if [ -e "${LOCK_FILE}" ]
then
  rm -f "${LOCK_FILE}"
fi

### Clean up temp files
for FILE in ${TMP_CONFIG} ${TMP_CONFIG}.sed
do
  if [ -f "${FILE}" ]
  then
    rm -f "${FILE}"
  fi
done

###
### Core functions
###

function log() {
    if [ ${LOGGING} = "verbose" ]
    then
        echo "$(printf '%(%c)T\n' -1): setsettings: $*" >> ${LOG_DIR}/${LOG_FILE} 2>&1
    fi
}

function cleanup() {
    log "Work complete"
    sync
    exit
}

function game_setting() {
    if [ -n "${1}" ]
    then
        SETTING=$(get_setting "${1}" "${PLATFORM}" "${ROM}")
        log "Fetch \"${1}\" \"${PLATFORM}\" \"${ROM}\"] (${SETTING})"
        echo ${SETTING}
    fi
}

function clear_setting() {
      log "Remove setting [${1}]"
      if [ ! -f "${TMP_CONFIG}.sed" ]
      then
          echo -n 'sed -i "/^'${1}'/d;' >${TMP_CONFIG}.sed
      else
          echo -n ' /^'${1}'/d;' >>${TMP_CONFIG}.sed
      fi
}

function flush_settings() {
    echo -n '" '${RETROARCH_CONFIG}' >/dev/null 2>&1' >>${TMP_CONFIG}.sed
    chmod 0755 ${TMP_CONFIG}.sed
    ${TMP_CONFIG}.sed >/dev/null 2>&1 ||:
    rm -f ${TMP_CONFIG}.sed
}

function add_setting() {
    if [ ! "${1}" = "none" ]
    then
        local OS_SETTING="$(game_setting ${1})"
    fi
    local RETROARCH_KEY="${2}"
    local RETROARCH_VALUE="${3}"
    if [ -z "${RETROARCH_VALUE}" ]& \
       [ ! "${1}" = "none" ]
    then
        RETROARCH_VALUE="${OS_SETTING}"
    fi
    clear_setting "${RETROARCH_KEY}"
    echo "${RETROARCH_KEY} = \"${RETROARCH_VALUE}\"" >>${TMP_CONFIG}
    log "Added setting: ${RETROARCH_KEY} = \"${RETROARCH_VALUE}\""
}

function match() {
    local seek="${1}"
    shift
    local myarray=(${@})
    if [[ "${myarray[*]}" =~ ${seek} ]]
    then
        local MATCH="1"
    else
        local MATCH="0"
    fi
    log "Match: [${seek}] [${MATCH}] (${myarray[*]})"
    echo ${MATCH}
}

###
### Game data functions
###

### Configure retroarch paths
function set_retroarch_paths() {
  for RPATH in assets_directory cache_directory            \
               cheat_database_path content_database_path   \
               content_database_path joypad_autoconfig_dir \
               libretro_directory libretro_info_path       \
               overlay_directory video_shader_dir
  do
    clear_setting "${RPATH}"
  done
  flush_settings
  cat <<EOF >>${RETROARCH_CONFIG}
assets_directory = "/tmp/assets"
cache_directory = "/tmp/cache"
cheat_database_path = "/tmp/database/cht"
content_database_path = "/tmp/database/rdb"
joypad_autoconfig_dir = "/tmp/joypads"
libretro_directory = "/tmp/cores"
libretro_info_path = "/tmp/cores"
overlay_directory = "~/overlays"
video_shader_dir = "/tmp/shaders"
EOF
}

### Configure retroarch hotkeys
function configure_hotkeys() {
    log "Configure hotkeys..."
    local MY_CONTROLLER

    # InputPlumber's virtual pad, which is what RetroArch reads. It became a
    # DualSense Edge when the back paddles were mapped, and the Edge's name
    # does not contain the plain DualSense's ("DualSense Edge Wireless" vs
    # "DualSense Wireless"). Matching only the plain one fell through to js0,
    # the built-in pad's raw device, and wrote its button numbers - hotkey 5,
    # exit 6 - for a controller whose SELECT and START are 8 and 9, so
    # SELECT+START stopped leaving RetroArch.
    if grep -q "Sony Interactive Entertainment DualSense Edge Wireless Controller" /proc/bus/input/devices; then
        MY_CONTROLLER="Sony Interactive Entertainment DualSense Edge Wireless Controller"
    elif grep -q "Sony Interactive Entertainment DualSense Wireless Controller" /proc/bus/input/devices; then
        MY_CONTROLLER="Sony Interactive Entertainment DualSense Wireless Controller"
    elif grep -q "js0" /proc/bus/input/devices; then
        MY_CONTROLLER=$(grep -b4 js0 /proc/bus/input/devices | awk 'BEGIN {FS="\""}; /Name/ {printf $2}')
    else
        MY_CONTROLLER=$(grep -b4 joypad /proc/bus/input/devices | awk 'BEGIN {FS="\""}; /Name/ {printf $2}')
    fi

    ### Remove any input settings retroarch may have added.
    sed -i '/input_player[0-9]/d' ${RETROARCH_CONFIG}

    if [ "$(get_setting system.autohotkeys)" == "1" ]
    then
        if [ -e "/tmp/joypads/${MY_CONTROLLER}.cfg" ]
        then
            cp /tmp/joypads/"${MY_CONTROLLER}.cfg" /tmp
            sed -i "s# = #=#g" /tmp/"${MY_CONTROLLER}.cfg"
            source /tmp/"${MY_CONTROLLER}.cfg"
            # Home + START leaves every emulator the same way, and in one
            # press: portarelauncher watches for it and closes whatever does
            # not quit by itself. RetroArch's confirmation would make its
            # press the only one that needs doing twice. Both names, since
            # 1.22 renamed quit_press_twice to confirm_quit and a config that
            # predates that still carries the old one.
            for HKEYSETTING in input_enable_hotkey_btn input_bind_hold            \
                               input_exit_emulator_btn input_fps_toggle_btn       \
                               input_menu_toggle_btn input_save_state_btn         \
                               input_load_state_btn input_toggle_fast_forward_btn \
                               input_toggle_fast_forward_axis input_rewind_axis   \
                               input_rewind_btn quit_press_twice confirm_quit \
                               input_game_guide_btn
            do
                clear_setting "${HKEYSETTING}"
            done
            flush_settings
            if [ -z ${input_enable_hotkey_btn+x} ]
            then
                echo 'input_enable_hotkey_btn = '\"${input_select_btn}\" >>${RETROARCH_CONFIG}
            else
                echo 'input_enable_hotkey_btn = '\"${input_enable_hotkey_btn}\" >>${RETROARCH_CONFIG}
            fi
            cat <<EOF >>${RETROARCH_CONFIG}
input_bind_hold = "${input_select_btn}"
input_exit_emulator_btn = "${input_start_btn}"
input_fps_toggle_btn = "${input_y_btn}"
input_menu_toggle_btn = "${input_x_btn}"
input_save_state_btn = "${input_r_btn}"
input_load_state_btn = "${input_l_btn}"
input_game_guide_btn = "${input_game_guide_btn:-nul}"
quit_press_twice = "false"
confirm_quit = "false"
EOF
            if [ -n "${input_r2_btn}" ] && \
               [ -n "${input_l2_btn}" ]
            then
                cat <<EOF >>${RETROARCH_CONFIG}
input_toggle_fast_forward_axis = "nul"
input_toggle_fast_forward_btn = "${input_r2_btn}"
input_rewind_axis = "nul"
input_rewind_btn = "${input_l2_btn}"
EOF
            elif [ -n "${input_r2_axis}" ] && \
                 [ -n "${input_l2_axis}" ]
            then
                cat <<EOF >>${RETROARCH_CONFIG}
input_toggle_fast_forward_axis = "${input_r2_axis}"
input_toggle_fast_forward_btn = "nul"
input_rewind_axis = "${input_l2_axis}"
input_rewind_btn = "nul"
EOF
            fi
            rm -f /tmp/"${MY_CONTROLLER}.cfg"
        fi
    fi
}

function set_ra_menudriver() {
    add_setting "retroarch.menu_driver" "menu_driver"
    local MENU_DRIVER=$(game_setting retroarch.menu_driver)
    case ${MENU_DRIVER} in
        rgui)
            add_setting "none" "menu_linear_filter" "true"
        ;;
    esac
}

function set_fps() {
    add_setting "showFPS" "fps_show"
}

function set_config_save() {
    add_setting "config_save_on_exit" "false"
}

function set_cheevos() {
    local USE_CHEEVOS=$(game_setting "retroachievements")
    local CHECK_CHEEVOS="$(match "${PLATFORM}" "${HAS_CHEEVOS[@]}")"
    if [ "${USE_CHEEVOS}" = 1 ] && \
       [ "${CHECK_CHEEVOS}" = 1 ]
    then
        add_setting "none" "cheevos_enable" "true"
        add_setting "retroachievements.username" "cheevos_username"
        add_setting "retroachievements.password" "cheevos_password"
        add_setting "none" "cheevos_cmd" "/usr/share/libretro/call_achievements_hooks.sh"
        add_setting "retroachievements.hardcore" "cheevos_hardcore_mode_enable"
        add_setting "retroachievements.leaderboards" "cheevos_leaderboards_enable"
        add_setting "retroachievements.verbose" "cheevos_verbose_enable"
        add_setting "retroachievements.screenshot" "cheevos_auto_screenshot"
        add_setting "retroachievements.richpresence" "cheevos_richpresence_enable"
        add_setting "retroachievements.challengeindicators" "cheevos_challenge_indicators"
        add_setting "retroachievements.testunofficial" "cheevos_test_unofficial"
        add_setting "retroachievements.badges" "cheevos_badges_enable"
        add_setting "retroachievements.active" "cheevos_start_active"
        local CHEEVOS_SOUND_ENABLE=$(game_setting "retroachievements.sound")
        if [ "${CHEEVOS_SOUND_ENABLE}" != "none" ]; then
            add_setting "none" "cheevos_unlock_sound_enable" "true"
            add_setting "retroachievements.sound" "cheevos_unlock_sound"
        else
            add_setting "none" "cheevos_unlock_sound_enable" "false"
        fi
    else
        add_setting "none" "cheevos_enable" "false"
    fi
}

function set_netplay() {
    USE_NETPLAY=$(game_setting "netplay")
    if [ "${USE_NETPLAY}" = 1 ]
    then
        add_setting "none" "savestate_auto_load" "false"
        add_setting "none" "savestate_auto_save" "false"
        add_setting "retroachievements.hardcore" "cheevos_hardcore_mode_enable" "false"
        add_setting "global.netplay.nickname" "netplay_nickname"
        add_setting "global.netplay.password" "netplay_password"
        add_setting "netplay_public_announce" "netplay_public_announce"
        local NETPLAY_MODE=$(game_setting "netplay.mode")
        local NETPLAY_PORT=$(game_setting "global.netplay.port")
        case ${NETPLAY_MODE} in
            host)
                add_setting "none" "netplay_mode" "false"
                add_setting "none" "netplay_client_swap_input" "false"
                add_setting "global.netplay.port" "netplay_ip_port" "${NETPLAY_PORT}"
                case ${CORE} in
                    gambatte)
                        log "Configuring gameboy link server."
                        if [ ! -d "${RETROARCH_PATH}/config/Gambatte" ]
                        then
                            mkdir -p "${RETROARCH_PATH}/config/Gambatte"
                        fi
                        local GAMBATTE_CONF="${RETROARCH_PATH}/config/Gambatte/Gambatte.opt"
                        ### Rework this to use add_setting and be configurable in ES.
                        sed -i '/gambatte_gb_link_mode/d; \
                                /gambatte_gb_link_network_port/d' ${GAMBATTE_CONF}
                        cat <<EOF >>${GAMBATTE_CONF}
gambatte_gb_link_mode = "Network Server"
gambatte_gb_link_network_port = "$(( ${NETPLAY_PORT} + 1 ))"
EOF
                    ;;
                    tgbdual)
                        log "Configuring tgbdual for network play"
                        if [ ! -d "${RETROARCH_PATH}/config/TGB Dual" ]
                        then
                            mkdir -p "${RETROARCH_PATH}/config/TGB Dual"
                        fi
                        local TGBDUAL_CONF="${RETROARCH_PATH}/config/TGB Dual/TGB Dual.opt"
                        sed -i '/tgbdual_gblink_enable/d; \
                                /tgbdual_single_screen_mp/d; \
                                /tgbdual_switch_screens/d; \
                                /tgbdual_audio_output/d' "${TGBDUAL_CONF}"
                        cat <<EOF >>"${TGBDUAL_CONF}"
tgbdual_gblink_enable = "enabled"
tgbdual_single_screen_mp = "player 1 only"
tgbdual_switch_screens = "normal"
tgbdual_audio_output = "Game Boy #1"
EOF
                        echo -n " --host"
                    ;;
                    genesis_plus_gx)
                        log "Configure genesis_plus_gx 4 way play."
                        add_setting "none" "input_libretro_device_p2" "1025"
                        echo -n " --host"
                    ;;

                    snes9x)
                        log "Configure snes9x multitap."
                        add_setting "none" "input_libretro_device_p2" "257"
                        echo -n " --host"
                    ;;
                    *)
                        echo -n " --host"
                    ;;
                esac
            ;;
            client)
                local NETPLAY_HOST_IP=$(get_setting global.netplay.host)
                add_setting "global.netplay.port" "${NETPLAY_PORT}"
                if [ ! -z "${NETPLAY_HOST_IP}" ]
                then
                    add_setting "none" "netplay_ip_address" "${NETPLAY_HOST_IP}"
                    case ${CORE} in
                        gambatte)
                            log "Configuring gameboy link client."
                            if [ ! -d "${RETROARCH_PATH}/config/Gambatte" ]
                            then
                                mkdir -p "${RETROARCH_PATH}/config/Gambatte"
                            fi
                            add_setting "none" "netplay_mode" "false"
                            add_setting "none" "netplay_client_swap_input" "false"
                            local GAMBATTE_CONF="${RETROARCH_PATH}/config/Gambatte/Gambatte.opt"
                            sed -i '/gambatte_gb_link_mode/d; \
                                    /gambatte_gb_link_network_port/d' ${GAMBATTE_CONF}
                            cat <<EOF >>${GAMBATTE_CONF}
gambatte_gb_link_mode = "Network Client"
gambatte_gb_link_network_port = "$(( ${NETPLAY_PORT} + 1 ))"
EOF

                            sed -i '/gambatte_gb_link_network_server_ip_/d'  ${GAMBATTE_CONF}

                            local IPARRAY=(${NETPLAY_HOST_IP//./ })
                            for ELEM in ${IPARRAY[*]}
                            do
                                ADDR="${ADDR}$(printf "%03d" "${ELEM}")"
                            done

                            local COUNT=1
                            for (( i=0; i<${#ADDR}; i++ ));
                            do
                                cat <<EOF >>${GAMBATTE_CONF}
gambatte_gb_link_network_server_ip_${COUNT} = "${ADDR:$i:1}"
EOF
                                COUNT=$(( ${COUNT} + 1 ))
                            done
                        ;;
                        tgbdual)
                            log "Configuring tgbdual for network play"
                            if [ ! -d "${RETROARCH_PATH}/config/TGB Dual" ]
                            then
                                mkdir -p "${RETROARCH_PATH}/config/TGB Dual"
                            fi
                            local TGBDUAL_CONF="${RETROARCH_PATH}/config/TGB Dual/TGB Dual.opt"
                            local PLAYER=$(get_setting wifi.adhoc.id)
                            if [ -z "${PLAYER}" ]
                            then
                                PLAYER=2
                            fi
                            sed -i '/tgbdual_gblink_enable/d; \
                                    /tgbdual_single_screen_mp/d; \
                                    /tgbdual_switch_screens/d; \
                                    /tgbdual_audio_output/d' "${TGBDUAL_CONF}"
                            cat <<EOF >"${TGBDUAL_CONF}"
tgbdual_gblink_enable = "enabled"
tgbdual_single_screen_mp = "player ${PLAYER} only"
tgbdual_switch_screens = "normal"
tgbdual_audio_output = "Game Boy #${PLAYER}"
EOF
                            add_setting "none" "netplay_mode" "true"
                            add_setting "none" "netplay_client_swap_input" "true"
                            echo -n " --connect ${NETPLAY_HOST_IP}"
                        ;;
                        *)
                            add_setting "none" "netplay_mode" "true"
                            add_setting "none" "netplay_client_swap_input" "true"
                            echo -n " --connect ${NETPLAY_HOST_IP}"
                        ;;
                    esac
                fi
            ;;
        esac
        local NETPLAY_RELAY=$(game_setting global.netplay.relay)
        if [ -n "${NETPLAY_RELAY}" ]
        then
          case ${NETPLAY_RELAY} in
              none|false|0)
                  add_setting "none" "netplay_use_mitm_server" "false"
              ;;
              custom)
                  add_setting "none" "netplay_use_mitm_server" "true"
                  add_setting "none" "netplay_mitm_server" "${NETPLAY_RELAY}"
                  add_setting "global.netplay.customserver" "netplay_custom_mitm_server"
              ;;
              *)
                  add_setting "none" "netplay_use_mitm_server" "true"
                  add_setting "none" "netplay_mitm_server" "${NETPLAY_RELAY}"
              ;;
          esac
        else
            add_setting "none" "netplay_use_mitm_server" "false"
        fi
    else
        add_setting "none" "netplay" "false"
    fi
}

function set_translation() {
    local USE_AI_SERVICE="$(game_setting ai_service_enabled)"
    case ${USE_AI_SERVICE} in
        0|false|none)
            add_setting "none" "ai_service_enable" "false"
        ;;
        *)
            add_setting "none" "ai_service_enable" "true"
            local AI_LANG="$(game_setting ai_target_lang)"
            local AI_URL="$(game_setting ai_service_url)"
            case ${AI_URL} in
              0|false|none)
                add_setting "none" "ai_service_url" "http://ztranslate.net/service?api_key=BATOCERA&mode=Fast&output=png&target_lang=${AI_LANG}"
              ;;
              *)
                add_setting "none" "ai_service_url" "${AI_URL}&mode=Fast&output=png&target_lang=${AI_LANG}"
              ;;
            esac
        ;;
    esac
}

function set_aspectratio() {
    local ASPECT_RATIO="$(game_setting ratio)"
    case ${ASPECT_RATIO} in
      0|false|none)
        add_setting "none" "aspect_ratio_index" "22"
      ;;
      *)
        for AR in ${!CORE_RATIOS[@]}
        do
            if [ "${CORE_RATIOS[${AR}]}" = "${ASPECT_RATIO}" ]
            then
                add_setting "none" "aspect_ratio_index" "${AR}"
                break
            fi
        done
      ;;
    esac
#    add_setting "positionx" "custom_viewport_x"
#    add_setting "positiony" "custom_viewport_y"
#    add_setting "width" "custom_viewport_width"
#    add_setting "height" "custom_viewport_height"
    add_setting "rotation" "video_rotation"
}

function set_filtering() {
    add_setting "smooth" "video_smooth"
}

# RetroArch paces frames and resamples audio against video_refresh_rate, so
# it has to be the rate of the mode the panel is actually in, not a number
# inherited from another device's config. The Nova panel exposes only
# 120 Hz, a per-game display_mode may pick another, and a dock brings a
# 60 Hz output. video_swap_interval 0 lets RetroArch pick the interval from
# the core's own rate, so 60 fps content at 120 Hz swaps every second
# refresh instead of running against the audio clock.
### The exact refresh rate of the mode the compositor is driving.
###
### wlr-randr answers from the Wayland protocol, which carries refresh as
### integer millihertz. A panel running 2 x NTSC - 120000/1001, or
### 119.88011988Hz - therefore reports as a flat 119.880, and RetroArch paces
### against a rate 1.2e-4Hz away from the one the panel is actually running.
### With black frame insertion on, that is a corrected frame, and so a visible
### flash, every 4.6 hours.
###
### The DRM modeline carries the pixel clock and both totals as integers, so
### the rational the kernel is driving can be recovered exactly rather than
### read back rounded. modetest is a query here, not a modeset: it needs no
### DRM master and leaves the compositor alone.
###
### The reported rate is still what says which mode is current, so it is
### passed in and used to pick the matching modeline. The tolerance is 0.002,
### comfortably above the 0.001 the millihertz rounding can move a rate and
### far below the gap between any two modes this panel would expose.
function exact_refresh_from_drm() {
    local REPORTED="${1}"
    /usr/bin/modetest -M msm -c 2>/dev/null | awk -v want="${REPORTED}" '
        /^[[:space:]]*#[0-9]+[[:space:]]/ {
            htot = $7 + 0; vtot = $11 + 0; clk = $12 + 0
            if (htot <= 0 || vtot <= 0 || clk <= 0) next
            rate = (clk * 1000.0) / (htot * vtot)
            if (want == "") { printf "%.6f", rate; exit }
            diff = rate - want
            if (diff < 0) diff = -diff
            if (diff < 0.002) { printf "%.6f", rate; exit }
        }'
}

function set_ra_refresh_rate() {
    local MODE="$(game_setting display_mode)"
    local RATE
    local EXACT
    case "${MODE}" in
        ""|default)
            RATE=$(/usr/bin/wlr-randr 2>/dev/null | awk '/current/ { for (i = 1; i <= NF; i++) if ($i == "Hz") { print $(i - 1); exit } }')
            EXACT="$(exact_refresh_from_drm "${RATE}")"
            if [ -n "${EXACT}" ]
            then
                log "Refresh rate ${RATE} refined to ${EXACT} from the DRM modeline"
                RATE="${EXACT}"
            fi

            ### SwanStation runs every NTSC PlayStation game at 59.8261 Hz,
            ### 480i included. Its rate is the CRTC clock over 3412.5 ticks
            ### x 263 lines - the line alternates 3413 and 3412 ticks since
            ### our 001-ntsc-line-is-3412-5-ticks patch, as on the console;
            ### upstream rounds it to 3413 and runs at 59.8173. The line
            ### count does not change when a game switches to interlaced
            ### output - measured, too: five minutes of Tekken 3's attract
            ### mode, a 480i game, reported one rate and never another. So
            ### one mode is exactly right for all of it, the N64's:
            ###
            ###   119.652237 / 59.8261 = 2.00000   exact
            ###   119.880120 / 59.8261 = 2.00380   +0.19%, a repeated
            ###                                    frame every ~9 s
            ###
            ### A per-game display_mode still pins another rate, and the
            ### case above handles it. See #228.
            ###
            ### The same for the other systems whose frame rate is not
            ### 59.94, each with a panel mode at exactly twice it:
            ###
            ###   Game Boy, Color, Advance  59.7275 = 4194304 / 70224
            ###                                     = 16777216 / 280896
            ###                             at 119.88 a frame repeated
            ###                             about every 2.3 s; 119.455 exact
            ###   Super Nintendo (NTSC)     60.0988 = 21477272.7 / 357366
            ###                             at 119.88 a frame dropped
            ###                             about every 3.2 s; 120.198 exact
            ###   NES (NTSC)                60.0988, the same clock and the
            ###                             same 357366 cycles (341 x 262
            ###                             dots, one skipped every other
            ###                             frame); 120.198 exact
            ###   Saturn (NTSC)             59.8261 = 28636363.6 / 478660
            ###                             (1820 dots x 263 lines), the
            ###                             PlayStation's and N64's rate;
            ###                             119.652 exact
            ###   Nintendo 64 (NTSC)        59.8261 = 48681812 / 813722
            ###                             at 119.88 a frame repeated
            ###                             about every 4.3 s; 119.652 exact
            ###   Sega, SMS to Mega CD      59.9227 = 53693175 / 896040
            ###                             at 119.88 a frame repeated
            ###                             about every 28 s; 119.846 exact
            ###   Neo Geo (FBNeo)           59.18, the board's 15625 / 264 =
            ###                             59.1856 kept in hundredths
            ###                             at 119.88 a frame repeated
            ###                             about every 0.7 s; 118.360 exact
            ###   Neo Geo CD (NeoCD)        59.5999 = 6042000 / 101376
            ###                             at 119.88 a frame repeated
            ###                             about every 1.5 s; 119.200 exact
            ###
            ### Asked for by rate rather than by index, so this does nothing
            ### at all on a panel without the mode rather than naming a rate
            ### the display cannot produce.
            local WANT="" WHY=""
            case "${CORE}" in
                swanstation)     WANT=119.6522; WHY="2 x 59.8261" ;;
                gambatte|mgba)   WANT=119.4550; WHY="2 x 59.7275" ;;
                snes9x|bsnes)    WANT=120.1976; WHY="2 x 60.0988" ;;
                nestopia)        WANT=120.1976; WHY="2 x 60.0988" ;;
                mednafen_saturn) WANT=119.6522; WHY="2 x 59.8261" ;;
                parallel_n64)    WANT=119.6522; WHY="2 x 59.8261" ;;
                genesis_plus_gx) WANT=119.8455; WHY="2 x 59.9227" ;;
                neocd)           WANT=119.1998; WHY="2 x 59.5999" ;;
                fbneo)
                    ### Only the Neo Geo: arcade boards run at anything from
                    ### 54 to 61 Hz, and no one mode fits them.
                    if [ "${PLATFORM}" = "neogeo" ]
                    then
                        WANT=118.3600; WHY="2 x 59.18, FBNeo's Neo Geo rate"
                    fi
                ;;
            esac
            if [ -n "${WANT}" ]
            then
                local EXACT_RATE
                EXACT_RATE="$(exact_refresh_from_drm "${WANT}")"
                if [ -n "${EXACT_RATE}" ]
                then
                    log "${CORE}: ${EXACT_RATE} is exactly ${WHY}, using it over ${RATE}"
                    RATE="${EXACT_RATE}"
                fi
            fi
        ;;
        *)
            RATE=$(echo "${MODE}" | tr -cd '[[:digit:]].')
        ;;
    esac

    # Leaving the rate unstated is not a neutral outcome. add_setting deletes
    # the key from the persistent config and supplies the value through the
    # appendconfig instead, so the first run that answers strips
    # video_refresh_rate from retroarch.cfg for good. A later run that cannot
    # answer -- wlr-randr with no compositor to ask, or a display_mode with no
    # digits in it -- then writes nothing over a key that is already gone, and
    # RetroArch falls back to its own default of 60 Hz on a 120 Hz panel. With
    # black frame insertion on that is the flicker. Fall back to the rate the
    # image shipped rather than say nothing.
    if [ -z "${RATE}" ]; then
        RATE=$(awk -F'"' '/^video_refresh_rate/ { print $2; exit }' \
               /usr/config/retroarch/retroarch.cfg 2>/dev/null)
    fi

    if [ -n "${RATE}" ]; then
        add_setting "none" "video_refresh_rate" "${RATE}"

        # Swap interval 0 means "work it out from the core's rate", which for
        # 60 fps content on the 120 Hz panel means holding each frame for two
        # refreshes. That is right until black frame insertion is on, and
        # then it is exactly wrong: BFI wants to put a black frame in the
        # gap, so it needs a frame presented on every refresh. With interval
        # 2 the real frame occupies two refreshes and the black frame two
        # more, which halves the real frame rate to 30 and flickers.
        local BFI
        BFI="$(grep -m1 '^video_black_frame_insertion' "${RETROARCH_CONFIG}" 2>/dev/null | tr -cd '[[:digit:]]')"
        if [ -n "${BFI}" ] && [ "${BFI}" != "0" ]
        then
            add_setting "none" "video_swap_interval" "1"
        else
            add_setting "none" "video_swap_interval" "0"
        fi
    fi
}

function set_integerscale() {
    add_setting "integerscale" "video_scale_integer"
    add_setting "integerscaleoverscale" "video_scale_integer_overscale"
}

function set_rgascale() {
    add_setting "rgascale" "video_ctx_scaling"
}

function set_shader() {
    local SHADER="$(game_setting shaderset)"
    case ${SHADER} in
        0|false|none)
            add_setting "none" "video_shader_enable" "false"
        ;;
        *)
            add_setting "none" "video_shader_enable" "true"
            add_setting "none" "video_shader" "${SHADER}"
            echo -n " --set-shader /tmp/shaders/${SHADER}"
        ;;
    esac
}

function set_filter() {
    local FILTER="$(game_setting videofilter)"
    case ${FILTER} in
        0|false|none)
            add_setting "none" "video_filter" ""
        ;;
        *)
            local FILTER_PATH="/usr/share/retroarch/filters"
            add_setting "none" "video_ctx_scaling" "false"
                add_setting "none" "video_filter" "${FILTER_PATH}/64bit/video/${FILTER}"
                add_setting "none" "video_filter_dir" "${FILTER_PATH}/64bit/video/"
                add_setting "none" "audio_filter_dir" "${FILTER_PATH}/64bit/audio"
        ;;
    esac
}

function set_overlay() {
    local BEZEL="$(game_setting bezel)"
    case ${BEZEL} in
        0|false|none)
        ;;
        *)
            write_bezel_config
            exit 0
        ;;
    esac

    local OVERLAY="$(game_setting overlayset)"
    case ${OVERLAY} in
        0|false|none)
            add_setting "none" "input_overlay_enable" "false"
            add_setting "none" "input_overlay" ""
        ;;
        *)
            local OVERLAY_PATH="/storage/overlays"
            add_setting "none" "input_overlay_enable" "true"
            add_setting "none" "input_overlay" "${OVERLAY_PATH}/${OVERLAY}"
        ;;
    esac
}

function set_rewind() {
    local REWIND="$(game_setting rewind)"
    case ${REWIND} in
        1)
            case $(match ${PLATFORM} ${NO_REWIND[@]}) in
                0)
                    add_setting "none" "rewind_enable" "true"
                ;;
                *)
                    add_setting "none" "rewind_enable" "false"
                ;;
            esac
        ;;
        *)
            add_setting "none" "rewind_enable" "false"
        ;;
    esac
}

function set_savestates() {
    local SAVESTATES="$(game_setting incrementalsavestates)"
    local MAXINCREMENTALSAVES="$(game_setting maxincrementalsaves)"
    case ${SAVESTATES} in
        0|false|none)
            add_setting "none" "savestate_auto_index" "false"
        ;;
        *)
            add_setting "none" "savestate_auto_index" "true"
        ;;
    esac
    add_setting "none" "savestate_max_keep" "${MAXINCREMENTALSAVES}"
}

function set_autosave() {
    local SETAUTOSAVE=false

    # argument overrides user setting
    case ${AUTOSAVE} in
        0)
            SETAUTOSAVE=false
        ;;
        1)
            SETAUTOSAVE=true
        ;;
        *)
            local AUTOSAVE_SETTING="$(game_setting autosave)"
            case ${AUTOSAVE_SETTING} in
                [1-3])
                   SETAUTOSAVE=true
                ;;
            esac
        ;;
    esac

    add_setting "none" "savestate_directory" "${SNAPSHOTS}/${PLATFORM}"
    if [ ! -d "${SNAPSHOTS}/${PLATFORM}" ]
    then
        mkdir "${SNAPSHOTS}/${PLATFORM}"
    fi

    if [ ! -z "${SNAPSHOT}" ]
    then
        add_setting "none" "state_slot" "${SNAPSHOT}"
    fi

    add_setting "none" "savestate_auto_load" "${SETAUTOSAVE}"
    add_setting "none" "savestate_auto_save" "${SETAUTOSAVE}"
}

function set_runahead() {
    local RUNAHEAD="$(game_setting runahead)"
    local HAS_RUNAHEAD="$(match ${PLATFORM} ${NO_RUNAHEAD[@]})"
    # Settings > Consoles in the launcher: <system>.profile is "latency" or
    # "visuals". Latency is RetroArch's preemptive frames, one frame: the
    # same savestate and core requirements as run-ahead, but the frame is
    # rerun only when the input changed, so idle play costs a savestate
    # per frame rather than a second emulation. An explicit runahead
    # count is classic run-ahead and wins; the two exclude each other.
    local PREEMPT="false"
    if [ "$(game_setting profile)" = "latency" ] && [ "${RUNAHEAD:-0}" -le 0 ]
    then
        PREEMPT="true"
    fi
    case ${HAS_RUNAHEAD} in
        1)
            add_setting "none" "run_ahead_enabled" "false"
            add_setting "none" "run_ahead_frames" "0"
            add_setting "none" "preemptive_frames_enable" "false"
        ;;
        *)
            if [ "${RUNAHEAD:-0}" -gt 0 ]
            then
                add_setting "none" "run_ahead_enabled" "true"
                add_setting "none" "run_ahead_frames" "${RUNAHEAD}"
                add_setting "secondinstance" "run_ahead_secondary_instance"
                add_setting "none" "preemptive_frames_enable" "false"
            elif [ "${PREEMPT}" = "true" ]
            then
                add_setting "none" "run_ahead_enabled" "false"
                add_setting "none" "run_ahead_frames" "1"
                add_setting "none" "preemptive_frames_enable" "true"
            else
                add_setting "none" "run_ahead_enabled" "false"
                add_setting "none" "run_ahead_frames" "0"
                add_setting "none" "preemptive_frames_enable" "false"
            fi
        ;;
    esac
}

function set_audiolatency() {
    add_setting "audiolatency" "audio_latency"
}

function set_analogsupport() {
    local HAS_ANALOG="$(match ${PLATFORM} ${NO_ANALOG[@]})"
    case ${HAS_ANALOG} in
        1)
            add_setting "none" "input_player1_analog_dpad_mode" "0"
        ;;
        *)
            add_setting "analogue" "input_player1_analog_dpad_mode" "1"
        ;;
    esac
}

function set_tatemode() {
    log "Setup tate mode..."
    if [ "${CORE}" = "mame2003_plus" ]
    then
        local TATEMODE="$(game_setting tatemode)"
        local MAME2003DIR="${RETROARCH_PATH}/config/MAME 2003-Plus"
        local MAME2003REMAPDIR="/storage/remappings/MAME 2003-Plus"
        if [ ! -d "${MAME2003DIR}" ]
        then
            mkdir -p "${MAME2003DIR}"
        fi
        if [ ! -d "${MAME2003REMAPDIR}" ]
        then
            mkdir -p "${MAME2003REMAPDIR}"
        fi
        case ${TATEMODE} in
            1|true)
                cp "/usr/config/retroarch/TATE-MAME 2003-Plus.rmp" "${MAME2003REMAPDIR}/MAME 2003-Plus.rmp"
                if [ "$(grep mame2003-plus_tate_mode "${MAME2003DIR}/MAME 2003-Plus.opt" > /dev/null 2>&1)" ]
                then
                    sed -i 's#mame2003-plus_tate_mode.*$#mame2003-plus_tate_mode = "enabled"#' "${MAME2003DIR}/MAME 2003-Plus.opt" 2>/dev/null
                else
                    echo 'mame2003-plus_tate_mode = "enabled"' > "${MAME2003DIR}/MAME 2003-Plus.opt"
                fi
            ;;
            *)
                if [ -e "${MAME2003DIR}/MAME 2003-Plus.opt" ]
                then
                    sed -i 's#mame2003-plus_tate_mode.*$#mame2003-plus_tate_mode = "disabled"#' "${MAME2003DIR}/MAME 2003-Plus.opt" 2>/dev/null
                fi
                if [ -e "${MAME2003REMAPDIR}/MAME 2003-Plus.rmp" ]
                then
                    rm -f "${MAME2003REMAPDIR}/MAME 2003-Plus.rmp"
                fi
            ;;
        esac
    fi
}

function set_n64opts() {
    log "Set up N64..."
    if [ "${CORE}" = "parallel_n64" ]
    then
        local PARALLELN64DIR="${RETROARCH_PATH}/config/ParaLLEl N64"
        if [ ! -d "${PARALLELN64DIR}" ]
        then
            mkdir -p "${PARALLELN64DIR}"
        fi

        if [ ! -f "${PARALLELN64DIR}/ParaLLEl N64.opt" ]
        then
            cp "/usr/config/retroarch/ParaLLEl N64.opt" "${PARALLELN64DIR}/ParaLLEl N64.opt"
        fi
        local VIDEO_CORE="$(game_setting parallel_n64_video_core)"
        sed -i '/parallel-n64-gfxplugin = /c\parallel-n64-gfxplugin = "'${VIDEO_CORE}'"' "${PARALLELN64DIR}/ParaLLEl N64.opt"
        local SCREENSIZE="$(game_setting parallel_n64_internal_resolution)"
        sed -i '/parallel-n64-screensize = /c\parallel-n64-screensize = "'${SCREENSIZE}'"' "${PARALLELN64DIR}/ParaLLEl N64.opt"
        local GAMESPEED="$(game_setting parallel_n64_gamespeed)"
        sed -i '/parallel-n64-framerate = /c\parallel-n64-framerate = "'${GAMESPEED}'"' "${PARALLELN64DIR}/ParaLLEl N64.opt"
        local ACCURACY="$(game_setting parallel_n64_gfx_accuracy)"
        sed -i '/parallel-n64-gfxplugin-accuracy = /c\parallel-n64-gfxplugin-accuracy = "'${ACCURACY}'"' "${PARALLELN64DIR}/ParaLLEl N64.opt"
        # 2x: a 640x480 game renders at the panel's 1280x960, and a
        # 320x240 one at 640x480, scaled 2x to the panel. 4x would suit
        # the low-res games and cost the hi-res ones 2560x1920. 2x also
        # when the setting is missing, as on an install from before it.
        local UPSCALING="$(game_setting parallel_n64_upscaling)"
        UPSCALING="${UPSCALING:-2x}"
        if grep -q '^parallel-n64-upscaling = ' "${PARALLELN64DIR}/ParaLLEl N64.opt"
        then
            sed -i '/parallel-n64-upscaling = /c\parallel-n64-upscaling = "'${UPSCALING}'"' "${PARALLELN64DIR}/ParaLLEl N64.opt"
        else
            echo "parallel-n64-upscaling = \"${UPSCALING}\"" >> "${PARALLELN64DIR}/ParaLLEl N64.opt"
        fi
        # A key the shipped options file gained after an install copied
        # it: added once with the shipped value, so an existing install gets
        # the new default. A value set since in RetroArch is left alone.
        for KEY in parallel-n64-parallel-rdp-vi-bilinear; do
            if ! grep -q "^${KEY} = " "${PARALLELN64DIR}/ParaLLEl N64.opt"; then
                grep "^${KEY} = " "/usr/config/retroarch/ParaLLEl N64.opt" >> "${PARALLELN64DIR}/ParaLLEl N64.opt"
            fi
        done
        local CONTROLLERPAK="$(game_setting parallel_n64_controller_pak)"
        sed -i '/parallel-n64-pak1 = /c\parallel-n64-pak1 = "'${CONTROLLERPAK}'"' "${PARALLELN64DIR}/ParaLLEl N64.opt"
    fi
}

function set_saturnopts() {
    log "Set up Saturn..."
    if [ "${CORE}" = "kronos" ]
    then
        log "Set up Kronos..."
        local KRONOSDIR="${RETROARCH_PATH}/Kronos/config/Kronos"
        if [ ! -d "${KRONOSDIR}" ]
        then
            mkdir -p "${KRONOSDIR}"
        fi

        if [ ! -f "${KRONOSDIR}/Kronos.opt" ]
        then
            cp "/usr/config/retroarch/Kronos.opt" "${KRONOSDIR}/Kronos.opt"
        fi
        local KRONOSOPT="${KRONOSDIR}/Kronos.opt"
        local HLE_BIOS="$(game_setting force_hle_bios)"
        sed -i '/kronos_force_hle_bios = /c\kronos_force_hle_bios = "'${HLE_BIOS}'"' "${KRONOSOPT}"
        local ADDON_CART="$(game_setting addon_cartridge)"
        sed -i '/kronos_addon_cartridge = /c\kronos_addon_cartridge = "'${ADDON_CART}'"' "${KRONOSOPT}"
        local TESSELATION="$(game_setting tesselation)"
        sed -i '/kronos_polygon_mode = /c\kronos_polygon_mode = "'${TESSELATION}'"' "${KRONOSOPT}"
        local RESOLUTION="$(game_setting resolution)"
        sed -i '/kronos_resolution_mode = /c\kronos_resolution_mode = "'${RESOLUTION}'"' "${KRONOSOPT}"
        local COMPUTE_SHADER="$(game_setting compute_shader)"
        sed -i '/kronos_use_cs = /c\kronos_use_cs = "'${COMPUTE_SHADER}'"' "${KRONOSOPT}"
        local TRANSPARENCY="$(game_setting transparency)"
        sed -i '/kronos_mesh_mode = /c\kronos_mesh_mode = "'${TRANSPARENCY}'"' "${KRONOSOPT}"
    fi
}

function set_dreamcastopts() {
    log "Set up Dreamcast..."
    if [ "${CORE}" = "flycast" ]
    then
        local FLYCASTDIR="${RETROARCH_PATH}/config/Flycast"
        if [ ! -d "${FLYCASTDIR}" ]
        then
            mkdir -p "${FLYCASTDIR}"
        fi

        if [ ! -f "${FLYCASTDIR}/Flycast.opt" ]
        then
            cp "/usr/config/retroarch/Flycast.opt" "${FLYCASTDIR}/Flycast.opt"
        fi
        local FRAME_SKIP="$(game_setting frame_skip)"
        sed -i '/flycast_auto_skip_frame = /c\flycast_auto_skip_frame = "'${FRAME_SKIP}'"' "${FLYCASTDIR}/Flycast.opt"
    fi
}

function set_psxopts() {
    log "Set up SwanStation..."
    if [ "${CORE}" = "swanstation" ]
    then
        # Settings > Consoles for the PlayStation. Visuals is the shipped
        # core: the Vulkan renderer at 4x, from retroarch-core-options.cfg.
        # Latency is the software renderer at 1x: the console's own
        # resolution, and savestates that carry no GPU state, which is what
        # makes a pre-emptive frame cheap enough to run every frame.
        # RetroArch reads per-core options from config/SwanStation when the
        # file exists, so it is made from the shipped global lines once.
        # The two keys are written when latency is on, and written back
        # to the shipped values once when it goes off; a renderer or scale
        # chosen in RetroArch's own menu under visuals is otherwise left
        # alone. The marker file says latency wrote them last.
        local SWANDIR="${RETROARCH_PATH}/config/SwanStation"
        local SWANOPT="${SWANDIR}/SwanStation.opt"
        local SHIPPED="/usr/config/retroarch/retroarch-core-options.cfg"
        local MARKER="${SWANDIR}/.latency-profile"
        local RENDERER SCALE
        if [ "$(game_setting profile)" = "latency" ]
        then
            RENDERER="Software"
            SCALE="1"
        elif [ -e "${MARKER}" ]
        then
            RENDERER="$(sed -n 's/^swanstation_GPU_Renderer = "\(.*\)"/\1/p' "${SHIPPED}")"
            SCALE="$(sed -n 's/^swanstation_GPU_ResolutionScale = "\(.*\)"/\1/p' "${SHIPPED}")"
            RENDERER="${RENDERER:-Vulkan}"
            SCALE="${SCALE:-4}"
        else
            return 0
        fi
        mkdir -p "${SWANDIR}"
        if [ ! -f "${SWANOPT}" ]
        then
            grep '^swanstation_' "${SHIPPED}" >"${SWANOPT}"
        fi
        for KEY in GPU_Renderer:"${RENDERER}" GPU_ResolutionScale:"${SCALE}"
        do
            local NAME="swanstation_${KEY%%:*}" VALUE="${KEY#*:}"
            if grep -q "^${NAME} = " "${SWANOPT}"
            then
                sed -i "/^${NAME} = /c\\${NAME} = \"${VALUE}\"" "${SWANOPT}"
            else
                echo "${NAME} = \"${VALUE}\"" >>"${SWANOPT}"
            fi
        done
        if [ "${RENDERER}" = "Software" ]
        then
            touch "${MARKER}"
        else
            rm -f "${MARKER}"
        fi
    fi
}

function set_melondsdsopts() {
    log "Set up melonDS DS..."
    if [ "${CORE}" = "melondsds" ]
    then
        local MELONDSDSDIR="${RETROARCH_PATH}/config/melonDS DS"
        if [ ! -d "${MELONDSDSDIR}" ]
        then
            mkdir -p "${MELONDSDSDIR}"
        fi

        if [ ! -f "${MELONDSDSDIR}/melonDS DS.opt" ]
        then
            cat <<EOF >"${MELONDSDSDIR}/melonDS DS.opt"
melonds_boot_mode = "direct"
melonds_console_mode = "ds"
melonds_show_cursor = "timeout"
melonds_touch_mode = "auto"
EOF
        fi

        if [ "${PLATFORM}" = "ndsiware" ]
        then
            sed -i '/melonds_console_mode = /c\melonds_console_mode = "dsi"' "${MELONDSDSDIR}/melonDS DS.opt"
        else
            sed -i '/melonds_console_mode = /c\melonds_console_mode = "ds"' "${MELONDSDSDIR}/melonDS DS.opt"
        fi

        if [ "${DEVICE_HAS_TOUCHSCREEN}" = "true" ]
        then
            sed -i '/melonds_show_cursor = /c\melonds_show_cursor = "disabled"' "${MELONDSDSDIR}/melonDS DS.opt"
            sed -i '/melonds_touch_mode = /c\melonds_touch_mode = "touch"' "${MELONDSDSDIR}/melonDS DS.opt"
        fi
    fi
}

function set_atari() {
    log "Set up Atari (FIXME)..."
    if [ "${CORE}" = "atari800" ]
    then
        ATARICONF="/storage/.config/system/configs/atari800.cfg"
        ATARI800CONF="${RETROARCH_PATH}/config/Atari800/Atari800.opt"
        if [ ! -f "$ATARI800CONF" ]
        then
            touch "$ATARI800CONF"
        fi
        sed -i "/RAM_SIZE=/d" ${ATARICONF}
        sed -i "/STEREO_POKEY=/d" ${ATARICONF}
        sed -i "/BUILTIN_BASIC=/d" ${ATARICONF}
        sed -i "/atari800_system =/d" ${ATARI800CONF}

        if [ "${PLATFORM}" == "atari5200" ]; then
            add_setting "none" "atari800_system" "5200"
            echo "atari800_system = \"5200\"" >> ${ATARI800CONF}
            echo "RAM_SIZE=16" >> ${ATARICONF}
            echo "STEREO_POKEY=0" >> ${ATARICONF}
            echo "BUILTIN_BASIC=0" >> ${ATARICONF}
        else
            add_setting "none" "atari800_system" "800XL (64K)"
            echo "atari800_system = \"800XL (64K)\"" >> ${ATARI800CONF}
            echo "RAM_SIZE=64" >> ${ATARICONF}
            echo "STEREO_POKEY=1" >> ${ATARICONF}
            echo "BUILTIN_BASIC=1" >> ${ATARICONF}
        fi
	flush_settings
    fi
}

function set_gambatte() {
    log "Set up Gambatte..."
    if [ "${CORE}" = "gambatte" ]
    then
        GAMBATTECONF="${RETROARCH_PATH}/config/Gambatte/Gambatte.opt"
        if [ ! -f "GAMBATTECONF" ]
        then
            echo 'gambatte_gbc_color_correction = "disabled"' > ${GAMBATTECONF}
        else
            sed -i "/gambatte_gb_colorization =/d" ${GAMBATTECONF}
            sed -i "/gambatte_gb_internal_palette =/d" ${GAMBATTECONF}
        fi
        local COLORIZATION=$(game_setting renderer.colorization)
        local TWB1_COLORIZATION=$(game_setting renderer.twb1_colorization)
        local TWB2_COLORIZATION=$(game_setting renderer.twb2_colorization)
        local TWB3_COLORIZATION=$(game_setting renderer.twb3_colorization)
        local PIXELSHIFT1_COLORIZATION=$(game_setting renderer.pixelshift1_colorization)

	if [ -n "${COLORIZATION}" ]
        then
            case ${COLORIZATION} in
                0|false|none)
                    echo 'gambatte_gb_colorization = "disabled"' >> ${GAMBATTECONF}
                ;;
                "Best Guess")
                    echo 'gambatte_gb_colorization = "auto"' >> ${GAMBATTECONF}
                ;;
                GBC|SGB)
                    echo 'gambatte_gb_colorization = "'${COLORIZATION}'"' >> ${GAMBATTECONF}
                ;;
                *)
                    echo 'gambatte_gb_colorization = "internal"' >> ${GAMBATTECONF}
                    echo 'gambatte_gb_internal_palette = "'${COLORIZATION}'"' >> ${GAMBATTECONF}
                    echo 'gambatte_gb_palette_twb64_1 = "'${TWB1_COLORIZATION}'"' >> ${GAMBATTECONF}
                    echo 'gambatte_gb_palette_twb64_2 = "'${TWB2_COLORIZATION}'"' >> ${GAMBATTECONF}
                    echo 'gambatte_gb_palette_twb64_3 = "'${TWB3_COLORIZATION}'"' >> ${GAMBATTECONF}
		            echo 'gambatte_gb_palette_pixelshift_1 = "'${PIXELSHIFT1_COLORIZATION}'"' >> ${GAMBATTECONF}
                ;;
            esac
        fi
    fi
}

function setup_controllers() {
    for i in $(seq 1 1 5)
    do
        log "Controller setup (${i})"
        if [[ "$CONTROLLERS" == *p${i}* ]]
        then
            PINDEX="${CONTROLLERS#*-p${i}index }"
            PINDEX="${PINDEX%% -p${i}guid*}"
            log "Set up controller ($i) (${PINDEX})"
            add_setting "none" "input_player${i}_joypad_index" "${PINDEX}"
            case ${PLATFORM} in
                atari5200)
                    add_setting "none" "input_libretro_device_p${i}" "513"
                ;;
            esac
        fi
    done
    flush_settings
}

# Function to write bezel configuration
write_bezel_config() {
    RETROARCH_OVERLAY_CONFIG="/tmp/.overlay.cfg"

    local json_output
    json_output=$(get_bezel_infos "${ROM}" "${BEZEL}" "${PLATFORM}" "retroarch")

    if [ $? -eq 0 ] && [ -n "$json_output" ]; then
        local bezel_png
        bezel_png=$(echo "$json_output" | jq -r '.png')

        if [ -n "$bezel_png" ] && [ -f "$bezel_png" ]; then
            cat > "$RETROARCH_OVERLAY_CONFIG" << EOF
overlays = 1
overlay0_overlay = "$bezel_png"
overlay0_full_screen = true
overlay0_descs = 0
EOF

            add_setting "none" "input_overlay_enable" "true"
            add_setting "none" "input_overlay" "${RETROARCH_OVERLAY_CONFIG}"
            return 0
        fi
    fi

    return 1
}

# Function to check bezel file existence
check_bezel_file() {
    local base_path="$1"
    local file_name="$2"

    if [ -f "${base_path}/${file_name}.png" ]; then
        bezel_png="${base_path}/${file_name}.png"
        if [ -f "${base_path}/${file_name}.info" ]; then
            bezel_info="${base_path}/${file_name}.info"
        elif [ -f "${base_path}/default.info" ]; then
            bezel_info="${base_path}/default.info"
        else
            bezel_info="${bezel_png}"
        fi
        return 0
    fi
    return 1
}

# Function to check decorations in a directory
check_decorations() {
    local base_path="$1"
    local system_name="$2"
    local rom_name="$3"

    if [ -d "${base_path}/games/${system_name}" ]; then
        if check_bezel_file "${base_path}/games/${system_name}" "${rom_name}"; then
            specific_to_game="true"
            return 0
        fi
    fi

    if [ -d "${base_path}/systems" ]; then
        if check_bezel_file "${base_path}/systems" "${system_name}"; then
            return 0
        fi
    fi

    if check_bezel_file "${base_path}" "default"; then
        return 0
    fi

    return 1
}

# Function to get bezel information
get_bezel_infos() {
    local rom="$1"
    local bezel="$2"
    local system="$3"
    local target="$4"

    # Initialize variables
    local bezel_info=""
    local bezel_png=""
    local layout_file=""
    local mame_zip=""
    local specific_to_game="false"

    # Check parameters
    if [ -z "$rom" ] || [ -z "$system" ] || [ -z "$target" ]; then
        return 1
    fi

    # Get ROM name without extension
    local rom_name=$(basename "${rom}")
    rom_name="${rom_name%.*}"

    # Check if bezel parameter is provided
    if [ -n "$bezel" ]; then
        local bezel_base_path="${BEZEL_DIR}/${bezel}"

        if check_decorations "${bezel_base_path}" "${system}" "${rom_name}"; then
            cat << EOF
{
    "png": "$bezel_png",
    "info": "${bezel_info}",
    "layout": "${layout_file:-null}",
    "mamezip": "${mame_zip:-null}",
    "specific_to_game": $specific_to_game
}
EOF
            return 0
        fi
    fi

    return 1
}

###
### Execute functions
###

###
### Functions that must be run without parallelization.
###

set_retroarch_paths
setup_controllers
configure_hotkeys

###
### Game specific functions
###

set_atari &
set_gambatte &

wait
flush_settings

###
### Functions that can execute in parallel.
###

set_ra_menudriver &
set_config_save &
set_fps &
set_cheevos &
set_translation &
set_aspectratio &
set_filtering &
set_integerscale &
set_ra_refresh_rate &
set_rgascale &
set_shader &
set_filter &
set_overlay &
set_rewind &
set_savestates &
set_autosave &
set_netplay &
set_runahead &
set_audiolatency &
set_analogsupport &
set_tatemode &
set_n64opts &
set_saturnopts &
set_dreamcastopts &
set_melondsdsopts &
set_psxopts &

### Sed operations are expensive, so they are staged and executed as
### a single process when all forks complete.
wait
flush_settings

cleanup
