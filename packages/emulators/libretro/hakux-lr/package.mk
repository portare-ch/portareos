# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="hakux-lr"
PKG_VERSION="0.11.0"
PKG_SHA256="0f5005724791d6f9519c32271ffe7872f1625c94ea59b9e075fb3d1abb943ae1"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/portare-ch/hakuX-lr"
PKG_URL="${PKG_SITE}/releases/download/linux-v${PKG_VERSION}/hakux-${PKG_VERSION}-aarch64.tar.gz"
PKG_SOURCE_DIR="hakux-${PKG_VERSION}"
PKG_DEPENDS_TARGET="toolchain zlib"
PKG_LONGDESC="hakuX as a libretro core: original Xbox games in RetroArch, drawn on RetroArch's Vulkan device."
PKG_TOOLCHAIN="manual"

# The core from hakuX's own release, which holds only the core since 0.4.0
# (tools/native/linux-package.sh in its repository). RetroArch hands it its
# Vulkan device, sound and controllers; its override (config/hakuX) keeps
# the console's disk in /storage/saves/xbox and run-ahead off.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro ${INSTALL}/usr/share/licenses/hakux
  cp -p ${PKG_BUILD}/lib/libretro/hakux_libretro.so ${PKG_BUILD}/lib/libretro/hakux_libretro.info \
    ${INSTALL}/usr/lib/libretro
  sed -i 's/^supported_extensions = "iso|chd"$/supported_extensions = "chd"/' \
    ${INSTALL}/usr/lib/libretro/hakux_libretro.info
  grep -q '^supported_extensions = "chd"$' \
    ${INSTALL}/usr/lib/libretro/hakux_libretro.info || exit 1
  cp -p ${PKG_BUILD}/share/licenses/hakux/* ${PKG_BUILD}/BUILD-INFO ${INSTALL}/usr/share/licenses/hakux
}
