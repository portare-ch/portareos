# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="glsl-shaders"
PKG_VERSION="ce9a41242e27f41e16bc35c28943466cee3e8ff8"
PKG_SHA256="6521587c3baaba2913cc7445800eea8eac3e6a7db7d47d69ab138778fca7876f"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/glsl-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Common GSLS shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/glsl-shaders" -C "${PKG_BUILD}"
}
