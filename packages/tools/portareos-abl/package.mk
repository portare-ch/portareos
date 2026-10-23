# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="portareos-abl"
PKG_VERSION="1.2"
PKG_SHA256="ee74f23f2b35ffa67a4741cd70c14a255709ead9b9e981ad4a62089ec22daf6c"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/portare-ch/BIOS"
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/portare-bios-v${PKG_VERSION}.tar.gz"
# The mirror and the build tree know the archive by its own name, which
# also names the folder it unpacks into.
PKG_SOURCE_NAME="portare-bios-v${PKG_VERSION}.tar.gz"
PKG_SOURCE_DIR="portare-bios-v${PKG_VERSION}"
PKG_LONGDESC="Portare BIOS, the bootloader updates flash to abl_a and abl_b."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/bootloader/portareos_abl
    cp -a ${PKG_BUILD}/${DEVICE}/abl_signed-${DEVICE}.elf ${INSTALL}/usr/share/bootloader/portareos_abl/abl_signed-${DEVICE}.elf
    cp -a ${PKG_DIR}/sources/* ${INSTALL}/usr/share/bootloader/portareos_abl
    mv ${INSTALL}/usr/share/bootloader/portareos_abl/flash_abl.sh.template ${INSTALL}/usr/share/bootloader/portareos_abl/flash_abl.sh
    sed -i "s/%DEVICE%/${DEVICE}/g" ${INSTALL}/usr/share/bootloader/portareos_abl/flash_abl.sh
}
