# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="hakux-sa"
PKG_VERSION="0.1.0"
PKG_SHA256="e1744444473d9665fb34a4a3592a7fcb6b1bdde4f8f7a8e953d5d86c1ee30262"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/portare-ch/hakuX"
PKG_URL="${PKG_SITE}/releases/download/linux-v${PKG_VERSION}/hakux-${PKG_VERSION}-aarch64.tar.gz"
PKG_SOURCE_DIR="hakux-${PKG_VERSION}"
PKG_DEPENDS_TARGET="toolchain SDL3 zlib"
PKG_LONGDESC="hakuX - an Xbox emulator: FEX runs the CPU, its own kernel replaces the BIOS, and the NV2A draws through Vulkan."
PKG_TOOLCHAIN="manual"

# The release is hakuX's own build (tools/native/linux-package.sh in its
# repository): FEX's embedding needs Clang and pinned sources this tree does
# not carry. It runs against the image's SDL3, zlib and C/C++ runtime.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin ${INSTALL}/usr/share/licenses/hakux
  cp -p ${PKG_BUILD}/bin/hakux ${INSTALL}/usr/bin
  cp -p ${PKG_DIR}/scripts/start_hakux.sh ${INSTALL}/usr/bin
  chmod 755 ${INSTALL}/usr/bin/hakux ${INSTALL}/usr/bin/start_hakux.sh
  cp -p ${PKG_BUILD}/share/licenses/hakux/* ${PKG_BUILD}/BUILD-INFO ${INSTALL}/usr/share/licenses/hakux
}
