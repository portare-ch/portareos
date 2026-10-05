# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="glsl-shaders"
PKG_VERSION="435612fe4f1023117b3aae48c88603fb413404a3"
PKG_SHA256="16e89c0028d700e0475cb415c2ec5cc36b6319ca8454952db5bf6bcdafb25ec7"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/glsl-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Common GSLS shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/glsl-shaders" -C "${PKG_BUILD}"
}
