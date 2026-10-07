# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="slang-shaders"
PKG_VERSION="1e0238f9fdd4668ce8212c31d80877af605d3b53"
PKG_SHA256="0f6c3d4fd128c1ac654c31a29e62dfc3df6f4d702ebd5e6870117457adfed995"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/slang-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Common SLANG shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/slang-shaders" -C "${PKG_BUILD}"
}
