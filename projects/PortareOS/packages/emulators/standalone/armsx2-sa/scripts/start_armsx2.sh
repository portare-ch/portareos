#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

. /etc/profile

#load gptokeyb support files
control-gen_init.sh
source /storage/.config/gptokeyb/control.ini
get_controls

#Check if ARMSX2 exists in .config
if [ ! -d "/storage/.config/ARMSX2" ]; then
    mkdir -p "/storage/.config/ARMSX2"
        cp -r "/usr/config/ARMSX2" "/storage/.config/"
fi

#Check if ARMSX2 ini exists in .config
if [ ! -f "/storage/.config/ARMSX2/inis/PCSX2.ini" ]; then
        cp -r "/usr/config/ARMSX2/inis/PCSX2.ini" "/storage/.config/ARMSX2/inis/"
fi

#Check if the gptokeyb mapping exists in .config
if [ ! -f "/storage/.config/ARMSX2/armsx2.gptk" ]; then
        cp -r "/usr/config/ARMSX2/armsx2.gptk" "/storage/.config/ARMSX2/"
fi

#Check if secrets ini exists in .config
if [ ! -f "/storage/.config/ARMSX2/inis/secrets.ini" ]; then
        cp -r "/usr/config/ARMSX2/inis/secrets.ini" "/storage/.config/ARMSX2/inis/"
fi

#Make ARMSX2 bios folder
if [ ! -d "/storage/roms/bios/armsx2" ]; then
    mkdir -p "/storage/roms/bios/armsx2"
fi

#Create PS2 savestates folder
if [ ! -d "/storage/roms/savestates/ps2" ]; then
    mkdir -p "/storage/roms/savestates/ps2"
fi

#Emulation Station Features
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
ASPECT=$(get_setting aspect_ratio "${PLATFORM}" "${GAME}")
FILTER=$(get_setting bilinear_filtering "${PLATFORM}" "${GAME}")
FPS=$(get_setting show_fps "${PLATFORM}" "${GAME}")
RATE=$(get_setting ee_cycle_rate "${PLATFORM}" "${GAME}")
SKIP=$(get_setting ee_cycle_skip "${PLATFORM}" "${GAME}")
HWDOWNLOAD=$(get_setting hw_download_mode "${PLATFORM}" "${GAME}")
GRENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
IRES=$(get_setting internal_resolution "${PLATFORM}" "${GAME}")
VSYNC=$(get_setting vsync "${PLATFORM}" "${GAME}")
ENABLE_WIDESCREEN_PATCHES=$(get_setting enable_widescreen_patches "${PLATFORM}" "${GAME}")

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
if [ "${CORES}" = "little" ]
then
  EMUPERF="${SLOW_CORES}"
elif [ "${CORES}" = "big" ]
then
  EMUPERF="${FAST_CORES}"
else
  #All..
  unset EMUPERF
fi

  # Latency settings, forced on every launch rather than shipped as defaults.
  #
  # armsx2 writes its whole in-memory config back to PCSX2.ini when it exits,
  # so anything set only in the shipped ini survives exactly until the first
  # clean exit and is then replaced by whatever the emulator held. The ini we
  # install also never reaches a device that has already booted: post-update
  # copies configs with --ignore-existing so it cannot clobber user settings.
  # Writing them here, before the emulator starts, is the only place that
  # holds for every launch on every device.
  #
  # VsyncQueueSize is frames the emulator may queue ahead of the GPU: at 2
  # that is up to two frames, ~33ms, of input delay on a 60Hz title.
  sed -i '/^VsyncQueueSize =/c\VsyncQueueSize = 0' /storage/.config/ARMSX2/inis/PCSX2.ini

  # The audio buffer is deliberately left where upstream put it. Cutting
  # BufferMS/OutputLatencyMS from 50/20 to 20/10 was tried on a Nova and
  # dropped audio audibly during cutscenes, with nothing in armsx2's own log
  # to show for it - it does not report underruns, so the only instrument
  # that caught it was listening. If this is revisited, move in smaller steps
  # and judge it by ear on an FMV-heavy scene, not by the log.

  #Aspect Ratio
	if [ "$ASPECT" = "0" ]
	then
  		sed -i '/^AspectRatio =/c\AspectRatio = 4:3' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi
	if [ "$ASPECT" = "1" ]
	then
  		sed -i '/^AspectRatio =/c\AspectRatio = 16:9' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi
	if [ "$ASPECT" = "2" ]
	then
  		sed -i '/^AspectRatio =/c\AspectRatio = Stretch' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi

  #Bilinear Filtering
        if [ "$FILTER" = "0" ]
        then
                sed -i '/^filter =/c\filter = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$FILTER" = "1" ]
        then
                sed -i '/^filter =/c\filter = 1' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$FILTER" = "2" ]
        then
                sed -i '/^filter =/c\filter = 2' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$FILTER" = "3" ]
        then
                sed -i '/^filter =/c\filter = 3' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

  #Graphics Backend
  #
  #The SDL frontend has one way onto the panel, VK_KHR_display, so the
  #renderer is Vulkan (14) or software (13) presenting through Vulkan.
  #OpenGL (12) would need an EGL surface and there is no compositor to
  #give one, so that choice is taken as Vulkan too. -1 lets the emulator
  #pick, which on this frontend is Vulkan.
	if [ "$GRENDERER" = "0" ]
	then
  		sed -i '/^Renderer =/c\Renderer = -1' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi
	if [ "$GRENDERER" = "1" ] || [ "$GRENDERER" = "2" ]
	then
  		sed -i '/^Renderer =/c\Renderer = 14' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi
        if [ "$GRENDERER" = "3" ]
        then
                sed -i '/^Renderer =/c\Renderer = 13' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

  #Internal Resolution
        if [ -n "$IRES" ] && [ "$IRES" != "0" ]
        then
                sed -i "/^upscale_multiplier =/c\upscale_multiplier = $IRES" /storage/.config/ARMSX2/inis/PCSX2.ini
        else
                sed -i '/^upscale_multiplier =/c\upscale_multiplier = 1' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

  #Show FPS
	if [ "$FPS" = "false" ]
	then
  		sed -i '/^OsdShowFPS =/c\OsdShowFPS = false' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi
	if [ "$FPS" = "true" ]
	then
  		sed -i '/^OsdShowFPS =/c\OsdShowFPS = true' /storage/.config/ARMSX2/inis/PCSX2.ini
	fi

  #EE Cycle Rate
        sed -i '/^EECycleRate =/c\EECycleRate = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        if [ "$RATE" = "0" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = -3' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$RATE" = "1" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = -2' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$RATE" = "2" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = -1' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$RATE" = "3" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$RATE" = "4" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = 1' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$RATE" = "5" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = 2' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$RATE" = "6" ]
        then
                sed -i '/^EECycleRate =/c\EECycleRate = 3' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

  #EE Cycle Skip
        sed -i '/^EECycleSkip =/c\EECycleSkip = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        if [ "$SKIP" = "0" ]
        then
                sed -i '/^EECycleSkip =/c\EECycleSkip = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$SKIP" = "1" ]
        then
                sed -i '/^EECycleSkip =/c\EECycleSkip = 1' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$SKIP" = "2" ]
        then
                sed -i '/^EECycleSkip =/c\EECycleSkip = 2' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$SKIP" = "3" ]
        then
                sed -i '/^EECycleSkip =/c\EECycleSkip = 3' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

#HW download mode
        sed -i '/^HWDownloadMode =/c\HWDownloadMode = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        if [ "$HWDOWNLOAD" = "0" ]
        then
                sed -i '/^HWDownloadMode =/c\HWDownloadMode = 0' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$HWDOWNLOAD" = "1" ]
        then
                sed -i '/^HWDownloadMode =/c\HWDownloadMode = 1' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$HWDOWNLOAD" = "2" ]
        then
                sed -i '/^HWDownloadMode =/c\HWDownloadMode = 2' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi
        if [ "$HWDOWNLOAD" = "3" ]
        then
                sed -i '/^HWDownloadMode =/c\HWDownloadMode = 3' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

#Widescreen patches
	if [ "$ENABLE_WIDESCREEN_PATCHES" = "true" ]
	then
  		sed -i '/^EnableWideScreenPatches =/c\EnableWideScreenPatches = true' /storage/.config/ARMSX2/inis/PCSX2.ini
        else
                sed -i '/^EnableWideScreenPatches =/c\EnableWideScreenPatches = false' /storage/.config/ARMSX2/inis/PCSX2.ini
        fi

#Retroachievements
  /usr/bin/cheevos_armsx2.sh

#Graphic driver fixes
@GRAPHICS@

#Display path.
#
#armsx2-sdl is upstream's handheld frontend: no Qt, no window. With
#WAYLAND_DISPLAY unset it takes the panel itself through VK_KHR_display,
#and the GS draws the on-screen menus (FullscreenUI). runemu.sh always
#sets KMSMODE for this emulator, so the launcher has dropped DRM master
#by the time we get here. The game's ini keeps every setting; nothing is
#configured from a UI.
  unset WAYLAND_DISPLAY

#Run ARMSX2 emulator
  export SDL_AUDIODRIVER=pipewire
  set_kill set "-9 armsx2-sdl"

# gptokeyb maps nothing here; it runs for its exit combo, which is the only
# way out of ARMSX2 short of the three-button kill in input_sense.
  ${GPTOKEYB} "armsx2-sdl" -c "/storage/.config/ARMSX2/armsx2.gptk" &
  ${EMUPERF} /usr/share/armsx2-sa/armsx2-sdl "${1}"
  kill -9 "$(pidof gptokeyb)"
