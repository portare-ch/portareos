# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="slang-shaders"
PKG_VERSION="0b3ff0b240f82f4cb5e5d0117f8f2080e2764cf7"
PKG_SHA256="4adedc3f15537a528dd5ebe35a722bc0621eca49f9402ce6a5e8666ead6a1386"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/slang-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Common SLANG shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/slang-shaders" -C "${PKG_BUILD}"
}
