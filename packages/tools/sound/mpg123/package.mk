# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="mpg123"
PKG_VERSION="1.33.7"
PKG_SHA256="31d0e35a4ca567ec9b5ebda6c3062bb4435d6d3eacd6ef0d95cadd7854dc03ee"
PKG_LICENSE="LGPL-2.1-only"
PKG_SITE="https://www.mpg123.org/"
PKG_URL="https://downloads.sourceforge.net/project/mpg123/mpg123/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain alsa-lib"
PKG_LONGDESC="A console based real time MPEG Audio Player for Layer 1, 2 and 3."
PKG_BUILD_FLAGS="-sysroot +pic"

PKG_CONFIGURE_OPTS_TARGET="--disable-shared \
                           --enable-static"

PKG_DEPENDS_TARGET+=" SDL2"
PKG_BUILD_FLAGS="+pic"

# sdl is the only output module built.
#
# mpg123 1.33 has no pipewire module: --with-audio offers alsa, tinyalsa, jack,
# oss, portaudio, pulse, sdl, sndio and a few for platforms this is not. pulse
# is banned, jack is unavailable because our pipewire is built
# -Dpipewire-jack=disabled, and alsa would work but only through pcm_pipewire.
# SDL2 here is built with SDL_PIPEWIRE=ON and SDL_PULSEAUDIO=OFF, with
# SDL_AUDIODRIVER=pipewire pinned in /etc/profile.
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
