# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Inherit PKG_VERSION, PKG_SHA256 and PKG_URL from the global recipe
# rather than restating them, so this cannot drift behind it again.
# Kept for the program selection below - blkdiscard and schedutils are ours,
# and the global recipe builds a different set.
. ${ROOT}/packages/sysutils/util-linux/package.mk

# Sourcing the global recipe also brings in its post_install, which enables
# swap.service. That unit is LibreELEC's swapfile mount and lives in the
# global recipe's system.d, not ours. PortareOS does swap through
# portareos-memory-manager, which reads the /etc/swap.conf written below, so
# the unit is neither shipped nor wanted, and enable_service dies on a file
# that is not there.
unset -f post_install
PKG_NAME="util-linux"
PKG_DEPENDS_HOST="ccache:host autoconf:host automake:host intltool:host libtool:host pkg-config:host"
PKG_DEPENDS_TARGET="toolchain libcap-ng"
PKG_DEPENDS_INIT="toolchain"
PKG_LONGDESC="A large variety of low-level system utilities that are necessary for a Linux system to function."
PKG_TOOLCHAIN="autotools"
PKG_BUILD_FLAGS="+pic:host"

UTILLINUX_CONFIG_DEFAULT="--disable-gtk-doc \
                          --disable-nls \
                          --disable-rpath \
                          --enable-tls \
                          --disable-all-programs \
                          --enable-chsh-only-listed \
                          --disable-bash-completion \
                          --disable-colors-default \
                          --disable-pylibmount \
                          --disable-pg-bell \
                          --disable-use-tty-group \
                          --disable-makeinstall-chown \
                          --disable-makeinstall-setuid \
                          --with-gnu-ld \
                          --without-selinux \
                          --without-audit \
                          --without-udev \
                          --without-ncurses \
                          --without-ncursesw \
                          --without-readline \
                          --without-slang \
                          --without-tinfo \
                          --without-utempter \
                          --without-util \
                          --without-libz \
                          --without-user \
                          --without-systemd \
                          --without-smack \
                          --without-python \
                          --without-systemdsystemunitdir"

PKG_CONFIGURE_OPTS_TARGET="${UTILLINUX_CONFIG_DEFAULT} \
                           --enable-libuuid \
                           --enable-libblkid \
                           --enable-libmount \
                           --enable-libsmartcols \
                           --enable-losetup \
                           --enable-fsck \
                           --enable-fstrim \
                           --enable-blkid \
                           --enable-blkdiscard \
                           --enable-schedutils \
                           --enable-lscpu \
                           --enable-fallocate \
                           --enable-setpriv"

if [ "${SWAP_SUPPORT}" = "yes" ]; then
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-swapon"
fi

if [ "${SWAP_SUPPORT}" = "yes" ]; then
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-zramctl"
fi

PKG_CONFIGURE_OPTS_HOST="--enable-shared \
                         --disable-static \
                         ${UTILLINUX_CONFIG_TARGET} \
                         --disable-makeinstall-chown \
                         --disable-makeinstall-setuid \
                         --enable-uuidgen \
                         --enable-rename \
                         --enable-libuuid"

PKG_CONFIGURE_OPTS_INIT="${UTILLINUX_CONFIG_DEFAULT} \
                         --enable-libblkid \
                         --enable-libmount \
                         --enable-fsck \
                         --enable-blkid"

if [ "${INITRAMFS_PARTED_SUPPORT}" = "yes" ]; then
  PKG_CONFIGURE_OPTS_INIT+=" --enable-mkfs --enable-libuuid --enable-btrfs"
fi

post_makeinstall_target() {
  if [ "${SWAP_SUPPORT}" = "yes" ]; then
    mkdir -p ${INSTALL}/etc
      cat ${PKG_DIR}/config/swap.conf | \
        sed -e "s,@ZRAM_SWAP_SIZE@,${ZRAM_SWAP_SIZE},g" \
            -e "s,@SWAP_ENABLED_DEFAULT@,${SWAP_ENABLED_DEFAULT},g" \
            -e "s,@SWAP_FILE_SIZE@,${SWAP_FILE_SIZE},g" \
            -e "s,@SWAP_PRIORITY@,${SWAP_PRIORITY:-auto},g" \
            -e "s,@KSM_ENABLE@,${KSM_ENABLE:-auto},g" \
            -e "s,@ZRAM_COMPRESSION_ALGO@,${ZRAM_COMPRESSION_ALGO},g" \
            > ${INSTALL}/etc/swap.conf
  fi
}
