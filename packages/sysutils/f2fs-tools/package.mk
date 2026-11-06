# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="f2fs-tools"
PKG_VERSION="1.16.0"
PKG_SHA256="208c7a07e95383fbd7b466b5681590789dcb41f41bf197369c41a95383b57c5e"
PKG_LICENSE="GPL-2.0-only"
PKG_SITE="https://git.kernel.org/pub/scm/linux/kernel/git/jaegeuk/f2fs-tools.git"
PKG_URL="https://git.kernel.org/pub/scm/linux/kernel/git/jaegeuk/f2fs-tools.git/snapshot/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain util-linux"
PKG_LONGDESC="F2FS formatting and filesystem checks for SD cards."
PKG_TOOLCHAIN="autotools"

# Link libf2fs statically. The kernel has no F2FS compression support.
PKG_CONFIGURE_OPTS_TARGET="--disable-shared \
                           --enable-static \
                           --without-selinux \
                           --without-lzo2 \
                           --without-lz4"

pre_configure_target() {
  # 1.16.0 typedefs bool, a keyword in C23, which GCC 15 and later default to.
  CFLAGS="${CFLAGS} -std=gnu17"
}

make_target() {
  make -C lib
  make -C mkfs
  make -C fsck
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/sbin
  cp -P mkfs/mkfs.f2fs fsck/fsck.f2fs ${INSTALL}/usr/sbin
}
