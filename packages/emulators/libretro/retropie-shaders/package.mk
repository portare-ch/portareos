# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="retropie-shaders"
PKG_VERSION="7ab98be403804fe45c71e616c75716eff471bf9c"
PKG_SHA256="e4195a83627a1da26f817e998ac05f00f45e81d62caa50bdeeb9f4ffcf42ca45"
PKG_LICENSE=""
PKG_SITE="https://github.com/RetroPie/common-shaders"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="Libretro common shaders from retropie"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/common-shaders
    cp -a ${PKG_BUILD}/* ${INSTALL}/usr/share/common-shaders
    rm -f ${INSTALL}/usr/share/common-shaders/{Makefile,configure}
}
