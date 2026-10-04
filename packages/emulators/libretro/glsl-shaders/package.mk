# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="glsl-shaders"
PKG_VERSION="f8e23ff880668f0f0e837a05a316534d82a7f31b"
PKG_SHA256="a4196a853e9eeacb41f875932ef2ddc4701beafca919347d3590360bbd7c65ed"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/glsl-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Common GSLS shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/glsl-shaders" -C "${PKG_BUILD}"
}
