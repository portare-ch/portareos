# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="hakux-lr"
PKG_VERSION="0.35.2"
PKG_SHA256="a4319a86403ef99b93a1199363b33f9c83c3843ca9f21bc8d3da5815c5df762c"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/portare-ch/hakuX-lr"
PKG_URL="${PKG_SITE}/releases/download/linux-v${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}-aarch64.tar.gz"
PKG_SOURCE_DIR="${PKG_NAME}-${PKG_VERSION}"
PKG_DEPENDS_TARGET="toolchain zlib"
PKG_LONGDESC="hakuX-lr runs original Xbox games in RetroArch using Vulkan."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  local core="${INSTALL}/usr/lib/libretro"
  local licenses="${INSTALL}/usr/share/licenses/${PKG_NAME}"
  mkdir -p "${core}" "${licenses}"
  cp -p "${PKG_BUILD}/lib/libretro/${PKG_NAME}_libretro.so" \
    "${PKG_BUILD}/lib/libretro/${PKG_NAME}_libretro.info" "${core}/"
  sed -i 's/^supported_extensions = "iso|chd"$/supported_extensions = "chd"/' \
    "${core}/${PKG_NAME}_libretro.info"
  grep -q '^supported_extensions = "chd"$' \
    "${core}/${PKG_NAME}_libretro.info" || exit 1
  cp -pR "${PKG_BUILD}/share/licenses/${PKG_NAME}/." "${PKG_BUILD}/BUILD-INFO" "${licenses}/"
}
