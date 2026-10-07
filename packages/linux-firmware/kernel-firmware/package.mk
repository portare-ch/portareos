# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="kernel-firmware"
PKG_VERSION="20260910"
PKG_SHA256="9dc6fa2fd55ca3e0f321fb14a9ad04511c6d53c5dc3b71686ab10ab4be3aec0b"
PKG_LICENSE="other"
PKG_SITE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/"
PKG_URL="https://cdn.kernel.org/pub/linux/kernel/firmware/linux-firmware-${PKG_VERSION}.tar.gz"
PKG_LONGDESC="kernel-firmware: kernel related firmware"
PKG_TOOLCHAIN="manual"

configure_package() {
  PKG_FW_SOURCE=${PKG_BUILD}/.copied-firmware
}

post_patch() {
  (
    cd ${PKG_BUILD}

    # Do not run check_whence.py against the copied firmware
    echo '#!/usr/bin/python3' > check_whence.py

    mkdir -p "${PKG_FW_SOURCE}"
      ./copy-firmware.sh --verbose "${PKG_FW_SOURCE}"
  )
}

# Installs what the device's list names, config/kernel-firmware.dat, and
# nothing else: linux-firmware is 1.5 GB of every vendor's blobs, and the
# Nova loads a handful.
makeinstall_target() {
  FW_TARGET_DIR=${INSTALL}/$(get_full_firmware_dir)

  find_file_path config/kernel-firmware.dat || die "no config/kernel-firmware.dat for ${DEVICE}"

  while read -r fwline; do
    [ -z "${fwline}" ] && continue
    [[ ${fwline} =~ ^#.* ]] && continue
    [[ ${fwline} =~ ^[[:space:]] ]] && continue

    eval "(cd ${PKG_FW_SOURCE} && find "${fwline}" >/dev/null)" || die "ERROR: Firmware pattern does not exist: ${fwline}"

    while read -r fwfile; do
      [ -d "${PKG_FW_SOURCE}/${fwfile}" ] && continue

      if [ -f "${PKG_FW_SOURCE}/${fwfile}" ]; then
        mkdir -p "$(dirname "${FW_TARGET_DIR}/${fwfile}")"
          cp -Lv "${PKG_FW_SOURCE}/${fwfile}" "${FW_TARGET_DIR}/${fwfile}"
      else
        echo "ERROR: Firmware file ${fwfile} does not exist - aborting"
        exit 1
      fi
    done <<<"$(cd ${PKG_FW_SOURCE} && eval "find "${fwline}"")"
  done <"${FOUND_PATH}"
}
