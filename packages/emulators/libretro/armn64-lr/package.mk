# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="armn64-lr"
PKG_VERSION="10141dbe40067bc9f96442a4d5bbfae4d9f1493f" # v1.4.1
PKG_SHA256="de101594a8a8cf8bb3b11bbda2c0ab601df245d8778819807f43e9f8fa7befc9"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/MagnominusGit/armN64"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain zlib"
PKG_LONGDESC="Nintendo 64 libretro core with AArch64 recompilers and Vulkan rendering."
PKG_TOOLCHAIN="cmake"
PKG_BUILD_FLAGS="-lto"

# The device toolchain chooses the CPU; the SDL app is not part of the image.
PKG_CMAKE_OPTS_TARGET="-DARMN64_TUNE=OFF -DARMN64_APP=OFF -DARMN64_VULKAN=ON"

make_target() {
  ninja armn64_libretro
}

makeinstall_target() {
  mkdir -p "${INSTALL}/usr/lib/libretro"
  cp -a armn64_libretro.so "${INSTALL}/usr/lib/libretro/"
  cp -a "${PKG_BUILD}/libretro/armn64_libretro.info" "${INSTALL}/usr/lib/libretro/"
}
