# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

. ${ROOT}/packages/addons/addon-depends/multimedia-tools-depends/mpg123/package.mk

PKG_DEPENDS_TARGET+=" SDL2"
PKG_BUILD_FLAGS="+pic"

# sdl is the only output module built.
#
# mpg123 1.33 has no pipewire module: --with-audio offers alsa, tinyalsa, jack,
# oss, portaudio, pulse, sdl, sndio and a few for platforms this is not. pulse
# is banned, jack is unavailable because our pipewire is built
# -Dpipewire-jack=disabled, and alsa would work but only through pcm_pipewire.
# SDL2 here is built with SDL_PIPEWIRE=ON and SDL_PULSEAUDIO=OFF, with
# SDL_AUDIODRIVER=pipewire pinned in /etc/profile, which is the route ARMSX2
# already takes.
#
# Three things link libmpg123 to decode with, and none of them runs the
# binary: SDL2_mixer, amiberry and easyrpg-lr. Building no output module at all
# would be defensible on that, but a PortMaster port can call anything on
# PATH, and one small module is cheaper than a silent player.
#
# openal-soft was in the dependencies and is not in that list at all, so it
# was never building anything. Dropped.
#
# Deliberately dropping the base recipe's --disable-shared --enable-static:
# four things link this, so it is built shared for them to share.
PKG_CONFIGURE_OPTS_TARGET="--with-audio=sdl"
