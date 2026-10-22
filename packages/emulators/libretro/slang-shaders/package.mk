# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="slang-shaders"
PKG_VERSION="d21f8a5abaabc4ee061b6c81f6f1255e09aab32a"
PKG_SHA256="3be8be2eb7bd5874d5bc6f5d087fd7c94b907b9ade21466312a4db34d57f6d0b"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/slang-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Common SLANG shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/slang-shaders" -C "${PKG_BUILD}"
}
