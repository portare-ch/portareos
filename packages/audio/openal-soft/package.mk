# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="openal-soft"
PKG_VERSION="1.25.2"
PKG_SHA256="fb27e5839aa11f0e5b9d33756965291fad5d6909ab928ea1f796f4a1a6877894"
PKG_LICENSE="LGPL-2.0-or-later"
PKG_SITE="http://www.openal.org/"
PKG_URL="https://github.com/kcat/openal-soft/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain alsa-lib"
PKG_LONGDESC="OpenAL Soft is a software implementation of the OpenAL 3D audio API."

PKG_CMAKE_OPTS_TARGET="-DALSOFT_BACKEND_OSS=off \
                       -DALSOFT_BACKEND_PULSEAUDIO=off \
                       -DALSOFT_BACKEND_WAVE=off \
                       -DALSOFT_EXAMPLES=off \
                       -DALSOFT_UTILS=off"

# PipeWire is first in openal-soft's backend list, but it is only compiled in
# when libpipewire-0.3 is visible, so depend on it and fail the build if not.
PKG_DEPENDS_TARGET+=" pipewire"
PKG_CMAKE_OPTS_TARGET+=" -DALSOFT_BACKEND_PIPEWIRE=on \
                         -DALSOFT_REQUIRE_PIPEWIRE=on"
