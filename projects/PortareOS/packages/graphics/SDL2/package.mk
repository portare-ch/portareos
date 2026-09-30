# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2018-present 5schatten (https://github.com/5schatten)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

# SDL2 by name, ABI and headers only. The source is sdl2-compat, which
# implements the SDL2 API on top of SDL3, so everything that links
# libSDL2-2.0.so.0 keeps linking it and SDL3 does the work underneath.
# The package name stays SDL2 because 65 recipes in this tree name it.
#
# Why: SDL2 2.32 never implemented wp_tearing_control. An SDL2 client
# under sway therefore cannot present without waiting for a vblank, so a
# frame that runs a hair late costs a whole one - on the 120 Hz panel
# that is 30 fps falling to 24, then 20. sway 1.11 offers the protocol
# and SDL3 speaks it.
#
# The backends move with it: wayland, kmsdrm, alsa, pipewire, vulkan and
# gles are all built by the SDL3 recipe, which already enables the same
# set this recipe used to. sdl2-compat itself has no backends and needs
# only SDL3's headers to build; it dlopens libSDL3.so.0 at runtime.

PKG_NAME="SDL2"
PKG_VERSION="2.32.72"
PKG_SHA256="a14d2f78dad8e83ef1039b6534ace4d14f11f5b11d023af989affd70ac1bb35e"
PKG_LICENSE="Zlib"
PKG_SITE="https://github.com/libsdl-org/sdl2-compat"
PKG_URL="${PKG_SITE}/releases/download/release-${PKG_VERSION}/sdl2-compat-${PKG_VERSION}.tar.gz"
PKG_SOURCE_DIR="sdl2-compat-${PKG_VERSION}"
PKG_DEPENDS_HOST="toolchain:host"
PKG_DEPENDS_TARGET="toolchain SDL3"
PKG_LONGDESC="The SDL2 API implemented on top of SDL3, so SDL2 applications get SDL3's backends"
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DSDL2COMPAT_STATIC=OFF \
                       -DSDL2COMPAT_TESTS=OFF \
                       -DSDL2COMPAT_INSTALL=ON \
                       -DSDL2COMPAT_INSTALL_TESTS=OFF \
                       -DSDL2COMPAT_INSTALL_CPACK=OFF \
                       -DSDL2COMPAT_WERROR=OFF"

post_makeinstall_target() {
  # sdl2-config reports /usr paths; the build needs them under sysroot.
  sed -e "s:\(['=LI]\)/usr:\\1${SYSROOT_PREFIX}/usr:g" -i ${SYSROOT_PREFIX}/usr/bin/sdl2-config

  # Upstream installs the pkg-config file as sdl2-compat.pc. Everything
  # that asks pkg-config for "sdl2", which is most of the emulators,
  # finds nothing at all without this.
  ln -sf sdl2-compat.pc ${SYSROOT_PREFIX}/usr/lib/pkgconfig/sdl2.pc

  rm -rf ${INSTALL}/usr/bin
}
