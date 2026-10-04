# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2019-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="bluez"
PKG_VERSION="5.87"
PKG_SHA256="26bdcf2cebd7310c6f598850606b037ef0c515fe6608ebc54d22c50c4c32b35f"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="http://www.bluez.org/"
PKG_URL="https://www.kernel.org/pub/linux/bluetooth/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain dbus glib readline systemd"
PKG_LONGDESC="Bluetooth Tools and System Daemons for Linux."
PKG_TOOLCHAIN="autotools"
PKG_BUILD_FLAGS="+lto"

if build_with_debug; then
  BLUEZ_CONFIG="--enable-debug"
else
  BLUEZ_CONFIG="--disable-debug"
fi

BLUEZ_CONFIG+=" --enable-monitor --enable-test"

PKG_CONFIGURE_OPTS_TARGET="--disable-dependency-tracking \
                           --disable-silent-rules \
                           --enable-library \
                           --enable-udev \
                           --disable-cups \
                           --disable-obex \
                           --enable-client \
                           --enable-systemd \
                           --enable-tools \
                           --enable-deprecated \
                           --enable-datafiles \
                           --disable-manpages \
                           --disable-experimental \
                           --enable-sixaxis \
                           --with-gnu-ld \
                           ${BLUEZ_CONFIG} \
                           storagedir=/storage/.cache/bluetooth"

pre_configure_target() {
  # bluez fails to build in subdirs
  cd ${PKG_BUILD}
    rm -rf .${TARGET_NAME}

  export LIBS="-lncurses"
}

post_configure_target() {
  libtool_remove_rpath libtool
}

post_makeinstall_target() {
  safe_remove ${INSTALL}/usr/lib/systemd
  safe_remove ${INSTALL}/usr/bin/bluemoon
  safe_remove ${INSTALL}/usr/bin/ciptool

  mkdir -p ${INSTALL}/etc/bluetooth
    cp src/main.conf ${INSTALL}/etc/bluetooth
    sed -i ${INSTALL}/etc/bluetooth/main.conf \
        -e "s|^#\[Policy\]|\[Policy\]|g" \
        -e "s|^#AutoEnable.*|AutoEnable=true|g" \
        -e "s|^#JustWorksRepairing.*|JustWorksRepairing=always|g"
    echo "[General]" >${INSTALL}/etc/bluetooth/input.conf
    echo "ClassicBondedOnly=false" >>${INSTALL}/etc/bluetooth/input.conf

  mkdir -p ${INSTALL}/usr/bin
    cp ${PKG_BUILD}/tools/btmgmt ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/usr/share/services
    cp -P ${PKG_DIR}/default.d/*.conf ${INSTALL}/usr/share/services

  # bluez looks in /etc/firmware/
    ln -sf /usr/lib/firmware ${INSTALL}/etc/firmware

  # kodi requires bluez pkgconfig
    cp -P ${PKG_BUILD}/lib/bluez.pc ${SYSROOT_PREFIX}/usr/lib/pkgconfig
}

post_install() {
  enable_service bluetooth-defaults.service
  enable_service bluetooth.service
  enable_service obex.service
}

# Sourcing the global recipe also brings in its post_install, which enables
# bluetooth-defaults.service and obex.service. Neither is ours: the image
# ships bluetooth.service alone, brought up on demand by autostart's
# portareos-bluetooth rather than enabled at build time, and obexd is not
# built at all because the recipe passes --disable-obex. Inheriting the
# function only makes enable_service die on units that are not there.
unset -f post_install
PKG_NAME="bluez"
PKG_SITE="http://www.bluez.org/"
PKG_DEPENDS_TARGET="toolchain dbus glib readline systemd json-c alsa-lib ncurses"
PKG_LONGDESC="Bluetooth Tools and System Daemons for Linux."
PKG_TOOLCHAIN="autotools"
PKG_BUILD_FLAGS="+lto"

if build_with_debug; then
  BLUEZ_CONFIG="--enable-debug"
else
  BLUEZ_CONFIG="--disable-debug"
fi

BLUEZ_CONFIG+=" --enable-monitor --enable-test"

PKG_CONFIGURE_OPTS_TARGET="--disable-dependency-tracking \
                           --disable-silent-rules \
                           --enable-library \
                           --enable-udev \
                           --disable-cups \
                           --disable-obex \
                           --enable-client \
                           --enable-systemd \
                           --enable-tools \
                           --enable-deprecated \
                           --enable-datafiles \
                           --disable-manpages \
                           --disable-experimental \
                           --enable-sixaxis \
                           --enable-sap \
                           --enable-a2dp \
                           --enable-avrcp \
                           --enable-btpclient \
                           --enable-midi \
                           --disable-mesh \
                           --enable-hid2hci \
                           --enable-experimental \
                           --enable-hid \
                           --with-gnu-ld \
                           ${BLUEZ_CONFIG} \
                           storagedir=/storage/.cache/bluetooth"

pre_configure_target() {
# bluez fails to build in subdirs
  cd ${PKG_BUILD}
    rm -rf .${TARGET_NAME}

  export LIBS="-lncursesw -ltinfo"
}

post_configure_target() {
  libtool_remove_rpath libtool
}

post_makeinstall_target() {
  safe_remove ${INSTALL}/usr/lib/systemd
  safe_remove ${INSTALL}/usr/bin/bluemoon
  safe_remove ${INSTALL}/usr/bin/ciptool
  safe_remove ${INSTALL}/usr/share/dbus-1

  mkdir -p ${INSTALL}/etc/dbus-1/system.d
    cp src/bluetooth.conf ${INSTALL}/etc/dbus-1/system.d

  mkdir -p ${INSTALL}/etc/bluetooth
    cp src/main.conf ${INSTALL}/etc/bluetooth
    sed -i ${INSTALL}/etc/bluetooth/main.conf \
        -e "s|^#AutoEnable.*|AutoEnable=true|g" \
        -e "s|^#JustWorksRepairing.*|JustWorksRepairing=always|g" \
        -e "s|^#ControllerMode.*|ControllerMode=dual|g" \
        -e "s|^#FastConnectable.*|FastConnectable=true|g"
    echo "[General]" >${INSTALL}/etc/bluetooth/input.conf
    echo "ClassicBondedOnly=false" >>${INSTALL}/etc/bluetooth/input.conf

  # bluez looks in /etc/firmware/
    ln -sf /usr/lib/firmware ${INSTALL}/etc/firmware

  # libbluetooth required for bluez-alsa
  #  sed -i 's/-lbluetooth//g' ${PKG_BUILD}/lib/bluez.pc
    cp -P ${PKG_BUILD}/lib/bluez.pc ${SYSROOT_PREFIX}/usr/lib/pkgconfig
    cp -rL ${PKG_BUILD}/lib/bluetooth ${SYSROOT_PREFIX}/usr/include/
}
