# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="SDL2_mixer"
PKG_VERSION="2.8.0"
PKG_SHA256="1cfb34c87b26dbdbc7afd68c4f545c0116ab5f90bbfecc5aebe2a9cb4bb31549"
PKG_LICENSE="GPLv3"
PKG_SITE="http://www.libsdl.org/projects/SDL_mixer/release"
PKG_URL="${PKG_SITE}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain opusfile alsa-lib SDL2 libogg libvorbis flac mpg123 libmodplug wavpack libxmp"
PKG_LONGDESC="SDL2 mixer"
PKG_TOOLCHAIN="cmake"

# No fluidsynth on the image: ScummVM, the one thing that played MIDI
# through it, synthesizes in its own core now. The tarball carries a
# CMakeLists.txt, so the auto-detected toolchain is cmake, and a
# configure-style --disable flag never reached it: FluidSynth stayed on
# and find_package(FluidSynth REQUIRED) failed. MIDI keeps timidity.
PKG_CMAKE_OPTS_TARGET="-DSDL2MIXER_MIDI_FLUIDSYNTH=OFF"
