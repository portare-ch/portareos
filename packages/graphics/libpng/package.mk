# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="libpng"
PKG_VERSION="1.6.58"
PKG_SHA256="28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775"
PKG_LICENSE="libpng-2.0"
PKG_SITE="http://www.libpng.org/"
PKG_URL="https://downloads.sourceforge.net/project/libpng/libpng16/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_HOST="zlib:host"
PKG_DEPENDS_TARGET="toolchain zlib"
PKG_LONGDESC="An extensible file format for the lossless, portable, well-compressed storage of raster images."
PKG_TOOLCHAIN="configure"
PKG_BUILD_FLAGS="+pic +pic:host"

PKG_CONFIGURE_OPTS_TARGET="ac_cv_lib_z_zlibVersion=yes \
                           --enable-static \
                           --disable-shared"

PKG_CONFIGURE_OPTS_HOST="--enable-static --disable-shared"

pre_configure_host() {
  export CPPFLAGS="${CPPFLAGS} -I${TOOLCHAIN}/include"
}

pre_configure_target() {
  export CPPFLAGS="${CPPFLAGS} -I${SYSROOT_PREFIX}/usr/include"
}

post_makeinstall_target() {
  sed -e "s:\([\"'= ]\)/usr:\\1${SYSROOT_PREFIX}/usr:g" \
      -e "s:libs=\"-lpng16\":libs=\"-lpng16 -lz\":g" \
      -i ${SYSROOT_PREFIX}/usr/bin/libpng*-config

  sed -e 's|^Libs: -L${libdir} -lpng16|Libs: -L${libdir} -lpng16 -lz|g' \
      -i ${SYSROOT_PREFIX}/usr/lib/pkgconfig/libpng*.pc

  rm -rf ${INSTALL}/usr/bin
}

# Upstream's recipe above; this fork's build configuration follows. An
# earlier copy sat on 1.6.40 while upstream carried 1.6.58 - eighteen patch
# releases of an image parser that every frontend on the device feeds
# untrusted files to - so the version above is the one to keep current.
PKG_DEPENDS_HOST="zlib:host"
PKG_DEPENDS_TARGET="toolchain zlib"
PKG_BUILD_FLAGS="+pic +pic:host"

# Shared on target, unlike upstream's options above: everything here links libpng
# dynamically, and a static one would be duplicated into each consumer.
PKG_CONFIGURE_OPTS_TARGET="ac_cv_lib_z_zlibVersion=yes \
                           --enable-static \
                           --enable-shared"

PKG_CONFIGURE_OPTS_HOST="--enable-static --disable-shared"

pre_configure_host() {
  export CPPFLAGS="$CPPFLAGS -I${TOOLCHAIN}/include"
}

pre_configure_target() {
  export CPPFLAGS="${CPPFLAGS} -I${SYSROOT_PREFIX}/usr/include"
}

post_makeinstall_target() {
  sed -e "s:\([\"'= ]\)/usr:\\1${SYSROOT_PREFIX}/usr:g" \
      -e "s:libs=\"-lpng16\":libs=\"-lpng16 -lz\":g" \
      -i ${SYSROOT_PREFIX}/usr/bin/libpng*-config

  rm -rf ${INSTALL}/usr/bin
}
