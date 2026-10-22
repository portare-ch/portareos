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
#   vendor_a firmware/{adsp,adsp_dtb}.mdt and their .bNN segments,
#            merged with linux-msm's pil-squasher into the .mbn files
#            the kernel's remoteproc loads; firmware/aw883xx_acf.bin,
#            the speaker amplifiers' tuning
#   modem_a  image/{cdsp,cdsp_dtb}.mdt and segments, the same way;
#            image/*.jsn as is
#
#   adsp.mbn  ADSP.HT.5.8-01329-KAILUA-1 (the Odin 2 file was 01153)
#             with the Nova's 5000 mAh battery profile (SA885G).
#             modem_a carries the same build with only the module's
#             SG8550 8000 mAh reference profile, which the gauge falls
#             back to when no profile matches the battery ID; the state
#             of charge then slews instead of following the current.
#             Android reports the SA885G profile, so it runs this copy.
#   cdsp.mbn  CDSP.HT.2.8-00906-KAILUA-1
#   aw883xx_acf.bin  144920 bytes; the Odin 2's, which the RP6 shares,
#                    is 85056
#
# The .jsn files are byte for byte the Odin 2's.

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)/qcom/sm8550/retroidpocket
  cp -a ${PKG_DIR}/firmware/rpnova ${INSTALL}/$(get_full_firmware_dir)/qcom/sm8550/retroidpocket/
}
