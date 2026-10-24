# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="slang-shaders"
PKG_VERSION="2b0530bac0e8083d9d643c194929dc0a6b69bd35"
PKG_SHA256="97427ee7a2b61257f2419314684ae5694ae68b645bae34d820c05254bb14551c"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/slang-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Common SLANG shaders for RetroArch"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  make install INSTALLDIR="${INSTALL}/usr/share/slang-shaders" -C "${PKG_BUILD}"
}
