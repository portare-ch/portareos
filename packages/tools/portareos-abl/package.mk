# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="portareos-abl"
PKG_VERSION="1.4.3"
PKG_SHA256="e7a061b1cdb0de2d886ceed1ced8e37eee9cb087e60997b89eb02c187eb3cfe7"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/portare-ch/BIOS"
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/abl_signed-${DEVICE}.elf"
# The release's image under a name with its version, for the source mirror
# and the build tree.
PKG_SOURCE_NAME="portare-bios-${PKG_VERSION}-${DEVICE}.elf"
PKG_LONGDESC="Portare BIOS, the bootloader updates flash to abl_a and abl_b."
PKG_TOOLCHAIN="manual"

# The source is the image itself, not an archive.
unpack() {
  mkdir -p ${PKG_BUILD}
  cp ${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME} ${PKG_BUILD}/abl_signed-${DEVICE}.elf
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/bootloader/portareos_abl
    cp -a ${PKG_BUILD}/abl_signed-${DEVICE}.elf ${INSTALL}/usr/share/bootloader/portareos_abl/abl_signed-${DEVICE}.elf
    cp -a ${PKG_DIR}/sources/* ${INSTALL}/usr/share/bootloader/portareos_abl
    mv ${INSTALL}/usr/share/bootloader/portareos_abl/flash_abl.sh.template ${INSTALL}/usr/share/bootloader/portareos_abl/flash_abl.sh
    sed -i "s/%DEVICE%/${DEVICE}/g" ${INSTALL}/usr/share/bootloader/portareos_abl/flash_abl.sh
}
