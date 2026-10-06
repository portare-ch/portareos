# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="p7zip"
PKG_VERSION="16.02"
PKG_SHA256="5eb20ac0e2944f6cb9c2d51dd6c4518941c185347d4089ea89087ffdd6e2341f"
PKG_LICENSE="GPL"
PKG_SITE="http://p7zip.sourceforge.net/"
PKG_URL="http://downloads.sourceforge.net/project/p7zip/p7zip/${PKG_VERSION}/p7zip_${PKG_VERSION}_src_all.tar.bz2"
PKG_DEPENDS_HOST="ccache:host"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="p7zip is a port of 7za.exe for POSIX systems like Unix."
PKG_TOOLCHAIN="manual"

pre_build_host() {
  rm -fr ${PKG_BUILD}/.${HOST_NAME}
  mkdir -p ${PKG_BUILD}/.${HOST_NAME}
  cp -RP ${PKG_BUILD}/* ${PKG_BUILD}/.${HOST_NAME}
}

make_host() {
  make CXX=${CXX} CC=${CC} -C ${PKG_BUILD}/.${HOST_NAME} 7za
}

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
    cp ${PKG_BUILD}/.${HOST_NAME}/bin/7za ${TOOLCHAIN}/bin
}

pre_build_target() {
  rm -fr ${PKG_BUILD}/.${TARGET_NAME}
  mkdir -p ${PKG_BUILD}/.${TARGET_NAME}
  cp -RP ${PKG_BUILD}/* ${PKG_BUILD}/.${TARGET_NAME}
}

make_target() {
  make CXX=${CXX} CC=${CC} -C ${PKG_BUILD}/.${TARGET_NAME} all3
}

# 7za only. The three binaries overlap almost completely: 7zr reads .7z and
# nothing else, and 7z is a thin front end that needs 7z.so (2.3MB) and the
# Codecs folder behind it, which together with the 7zCon.sfx stub is 3.9MB
# for formats nothing here opens. 7za is the standalone one and handles 7z,
# zip, tar, gzip and bzip2 by itself.
#
# Nothing on the image called any of them: RetroArch has 7-Zip compiled in
# rather than shelling out. The host
# build still gets 7za through makeinstall_host above, which is what the
# package system extracts with.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
    cp -p ${PKG_BUILD}/.${TARGET_NAME}/bin/7za ${INSTALL}/usr/bin
}
