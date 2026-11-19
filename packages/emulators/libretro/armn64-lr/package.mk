# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="armn64-lr"
PKG_VERSION="b071663e581fb59ce1cd8dff67658efd71ed37bf" # v1.4
PKG_SHA256="30561ce042dad2e95d03aca035bfba9c1ffde5fada9a0898ca71dc81506fe339"
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
