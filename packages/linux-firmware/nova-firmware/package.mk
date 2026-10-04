# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="nova-firmware"
PKG_VERSION="RPN07220904"
PKG_LICENSE="proprietary"
PKG_SITE="https://www.goretroid.com"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="The Retroid Pocket Nova's own ADSP, CDSP and speaker amplifier firmware"
PKG_TOOLCHAIN="manual"

# From the Nova's Android 13 build RPN07220904 (vendor incremental
# eng.RPN.20260722.090913), read off a Nova's own partitions:
#
#   modem_a  image/{adsp,adsp_dtb,cdsp,cdsp_dtb}.mdt and their .bNN
#            segments, merged with linux-msm's pil-squasher into the
#            .mbn files the kernel's remoteproc loads; image/*.jsn as is
#   vendor_a firmware/aw883xx_acf.bin, the speaker amplifiers' tuning
#
#   adsp.mbn  ADSP.HT.5.8-01329-KAILUA-1 (the Odin 2 file was 01153)
#   cdsp.mbn  CDSP.HT.2.8-00906-KAILUA-1
#   aw883xx_acf.bin  144920 bytes; the Odin 2's, which the RP6 shares,
#                    is 85056
#
# The .jsn files are byte for byte the Odin 2's.

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)/qcom/sm8550/retroidpocket
  cp -a ${PKG_DIR}/firmware/rpnova ${INSTALL}/$(get_full_firmware_dir)/qcom/sm8550/retroidpocket/
}
