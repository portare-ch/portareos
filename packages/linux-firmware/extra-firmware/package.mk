# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="extra-firmware"
PKG_VERSION="30c56e2f34af37fe372166b739d6ab277f5155b5"
PKG_SHA256="b6e422b953fec72666a84c0060f1ac32dd3fce452a6d6311e5051ab923497600"
PKG_LICENSE="proprietary"
PKG_SITE="https://github.com/ROCKNIX/extra-firmware"
PKG_URL="https://github.com/ROCKNIX/extra-firmware/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="extra-firmware: Extra kernel firmware needed for PortareOS devices"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)
    cp -a SM8550/* ${INSTALL}/$(get_full_firmware_dir)

  # ROCKNIX's SM8550 folder carries every SM8550 handheld's firmware. The
  # Nova loads its own DSP firmware, from nova-firmware, so none of the AYN
  # or AYANEO devices' is ever loaded here; nor are the APS and Thor audio
  # topologies, since its card is AYN-Odin2, nor the Renesas USB 3
  # controller's, which it does not have. Wi-Fi (ath12k), the video decoder
  # (qcom/vpu) and AYN-Odin2-tplg.bin stay.
  FW=${INSTALL}/$(get_full_firmware_dir)
  rm -rf ${FW}/qcom/sm8550/ayaneo ${FW}/qcom/sm8550/ayn
  rm -f ${FW}/qcom/sm8550/SM8550-APS-tplg.bin ${FW}/qcom/sm8550/AYN-Thor-tplg.bin
  rm -f ${FW}/renesas_usb_fw.mem

  python3 ${PKG_DIR}/sources/tplg-playback-rates.py \
    ${INSTALL}/$(get_full_firmware_dir)/qcom/sm8550/AYN-Odin2-tplg.bin

  # Runs second: its IN_SHA256 is the file the script above produces.
  python3 ${PKG_DIR}/sources/tplg-pull-mode.py \
    ${INSTALL}/$(get_full_firmware_dir)/qcom/sm8550/AYN-Odin2-tplg.bin
}
