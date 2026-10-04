# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="inputplumber"
PKG_VERSION="v0.79.0"
PKG_SHA256="123c858139d3b78e3f075158ce16b8fdc8067a10e31a93cb1e7f2aea816106bd"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/ShadowBlip/InputPlumber"
PKG_URL="https://github.com/ShadowBlip/InputPlumber/releases/download/${PKG_VERSION}/inputplumber-aarch64.tar.gz"
PKG_DEPENDS_TARGET="toolchain systemd libevdev libiio polkit"
PKG_LONGDESC="Open source input router and remapper daemon for Linux"
PKG_TOOLCHAIN="manual"

# Upstream composite device configs, dropped for two different reasons.
#
# 50-retroid_pocket_nova.yaml is the one that matters: it matches this device
# and would claim the same source device as ours,
# devices/SM8550/filesystem/usr/share/inputplumber/devices, which maps the
# gamepad to a ds5-edge target so the back buttons arrive as the Edge's real
# back-lever buttons. Two composite devices cannot own one evdev node.
#
# The rest are for handhelds this fork does not run. They would never match a
# Retroid Pocket Nova, so they are inert rather than harmful; they go because
# carrying other devices' input maps in a one-device tree is what made ours
# take an AYN name for years.
PKG_DROP_DEVICE_CONFIGS="
  50-ayaneo_pocket_s2.yaml
  50-ayn_odin2.yaml
  50-ayn_odin2_mini.yaml
  50-ayn_odin3.yaml
  50-ayn_thor.yaml
  50-konkr_pocket_fit.yaml
  50-konkr_pocket_fit_elite.yaml
  50-retroid_pocket5.yaml
  50-retroid_pocket6.yaml
  50-retroid_pocket_flip2.yaml
  50-retroid_pocket_mini.yaml
  50-retroid_pocket_nova.yaml
"

post_unpack() {
  for config in ${PKG_DROP_DEVICE_CONFIGS}; do
    rm -f ${PKG_BUILD}/usr/share/inputplumber/devices/${config}
  done
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr
  rsync -ar ${PKG_BUILD}/usr/ ${INSTALL}/usr/

  # sources/ is overlaid with cp, so pin the mode udev needs to run the shim.
  chmod 0755 ${INSTALL}/usr/lib/inputplumber/setfacl-shim/setfacl
}

post_install() {
  enable_service inputplumber.service
}
