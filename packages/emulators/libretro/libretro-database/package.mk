# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)
# Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)

PKG_NAME="libretro-database"
PKG_VERSION="bf825e3ec48d43557ad024da6a7b93e512043525"
PKG_SHA256="767c0e4688030f48b9788826a103ea97c1efcf5261012f364f17bcc2022b4258"
PKG_LICENSE=""
PKG_SITE="https://github.com/libretro/libretro-database"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="RetroArch's cheat files, for the systems this image ships"
PKG_TOOLCHAIN="manual"

# Only the cheats, and only for our systems. The rdb scanner database
# was never installed (the launcher scans folders itself), and the cheats
# for every system there is came to 172 MB, 97 of them for the DS alone.
# These are the cheat folders RetroArch reads under /tmp/database/cht for
# the cores we build; a folder upstream renames fails the copy, which is
# the right time to notice.
PKG_CHEAT_SYSTEMS=(
  "FBNeo - Arcade Games"
  "Nintendo - Family Computer Disk System"
  "Nintendo - Game Boy"
  "Nintendo - Game Boy Advance"
  "Nintendo - Game Boy Color"
  "Nintendo - Nintendo 64"
  "Nintendo - Nintendo Entertainment System"
  "Nintendo - Satellaview"
  "Nintendo - Super Nintendo Entertainment System"
  "Sega - 32X"
  "Sega - Dreamcast"
  "Sega - Game Gear"
  "Sega - Master System - Mark III"
  "Sega - Mega Drive - Genesis"
  "Sega - Mega-CD - Sega CD"
  "Sega - Saturn"
  "Sega - SG-1000"
  "Sony - PlayStation"
  "Sony - PlayStation Portable"
)

makeinstall_target() {
  local DB=${INSTALL}/usr/share/libretro-database
  mkdir -p ${DB}/cht
    cp -a ${PKG_BUILD}/cursors ${DB}/
    for system in "${PKG_CHEAT_SYSTEMS[@]}"; do
      cp -a "${PKG_BUILD}/cht/${system}" ${DB}/cht/
    done
  find ${DB} -type f \( -name "*.zip" -o -name "*.xml" \) -delete
}
