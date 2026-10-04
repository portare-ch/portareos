# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="armsx2-turnip"
PKG_VERSION="axfl2-001"
PKG_SHA256="4fd58e440d282981a639218d21ca52fe4dbed9981b4bc1f81697ee9d6e800d9b"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/bmdhacks/armsx2-turnip"
PKG_URL="${PKG_SITE}/releases/download/${PKG_VERSION}/turnip-${PKG_VERSION}-aarch64.tar.gz"
# What the prebuilt driver links against; all of it is in the image already.
PKG_DEPENDS_TARGET="toolchain expat zlib zstd libdrm wayland systemd"
PKG_LONGDESC="ARMSX2's Turnip: the Vulkan driver build its GS is tuned for, used by the PS2 core only."
# The ARMSX2 team's own build, unmodified: Mesa with their Turnip changes,
# which ARMSX2 2.7.2 trusts on the Adreno 740 (driverInfo "git-axfl2-") to
# order a declared feedback loop, so it drops its own barriers there (#497).
# Carrying their patches in our Mesa was judged too costly to maintain.
#
# Installed outside the loader's search path: nothing picks it up unless
# VK_DRIVER_FILES names it, which runemu does for the armsx2 core alone. The
# image's Mesa stays every other program's driver.
#
# It is stock Mesa apart from Turnip, so it lacks our mesa-002 patch: taking
# the display, it clears the CRTC's colour stages. With the default
# display.colorprofile=stock those are empty and nothing changes; with
# gamma22 or srgb, PS2 games show the panel uncorrected.
#
# To bump: take the release's aarch64 tarball and its .sha256, set
# PKG_VERSION and PKG_SHA256. The ARMSX2 core must be new enough to trust the
# tag the release carries.
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  local SRC="${PKG_BUILD}/${PKG_VERSION}"
  local DIR="/usr/lib/armsx2-turnip"

  # The release's own checksums, over what is installed.
  (cd "${SRC}" && sha256sum -c --quiet SHA256SUMS) || die "armsx2-turnip: SHA256SUMS mismatch"

  mkdir -p "${INSTALL}${DIR}"
  cp -a "${SRC}/libvulkan_freedreno.so" "${INSTALL}${DIR}"
  # The shipped manifest points at /storage/turnip/<tag>; keep the rest of it.
  sed -e "s#\"library_path\": \"[^\"]*\"#\"library_path\": \"${DIR}/libvulkan_freedreno.so\"#" \
    "${SRC}/freedreno_icd.aarch64.json" >"${INSTALL}${DIR}/freedreno_icd.aarch64.json"
  grep -q "\"${DIR}/libvulkan_freedreno.so\"" "${INSTALL}${DIR}/freedreno_icd.aarch64.json" ||
    die "armsx2-turnip: could not point the ICD manifest at ${DIR}"
}
