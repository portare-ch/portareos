# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="image"
PKG_LICENSE="GPL"
PKG_SITE="https://libreelec.tv"

PKG_SECTION="virtual"
PKG_LONGDESC="Root package used to build and create complete image"

PKG_DEPENDS_TARGET="toolchain squashfs-tools:host dosfstools:host fakeroot:host kmod:host \
                    mtools:host populatefs:host libc gcc linux linux-drivers linux-firmware \
                    ${BOOTLOADER} busybox lsof umtprd util-linux jq socat \
                    p7zip file initramfs grep util-linux btrfs-progs zstd lz4 empty lzo libzip \
                    bash coreutils system-utils autostart quirks powerstate \
                    gzip six xmlstarlet pyudev dialog network portareos"

# mako-osd is gone with the compositor. It is a wayland notification daemon
# and depends on sway by name, so leaving it here would pull the compositor
# straight back into the image. The volume and brightness OSD goes with it
# until the launcher draws its own - it is the only thing that can, now that
# it holds the panel.

# The front-end. portarelauncher owns the panel through KMS, so there is no
# compositor and no session here - see portareos#222.
#
# What EmulationStation carried along is gone with it: textviewer and
# sdl2notify were only ever started from its Tools menu, lowerdeck is the
# second-screen UI of dual-screen handhelds and the Nova has one screen,
# poppler rendered PDF manuals for ES, and nothing on the device calls
# ImageMagick at all. The gamepad tester stays, reached from the launcher's
# Tools entry. The file manager went too: files are managed over SSH, and
# its one screen, drawn once, never reached a KMS panel anyway.
PKG_UI="portarelauncher"

# grim went with the compositor: it screenshots a wayland output and there
# is no longer one. fbgrab reads /dev/fb0, which is not what the panel shows
# either - the launcher and VulkanDirect scan out their own buffers - so it
# goes too. Only whoever holds DRM master can read the panel now, so a
# screenshot belongs in the launcher if it comes back at all.
PKG_UI_TOOLS=""

PKG_GRAPHICS=""

PKG_FONTS="corefonts"

PKG_MULTIMEDIA="ffmpeg mpv gmu"

# espeak spoke EmulationStation's menus; EmulationStation is gone.
PKG_SOUND=""

# rclone and syncthing, 89 MB between them, were switched on and driven from
# EmulationStation's menus. rsync stays: the network package brings it, and
# it is what copying over ssh wants.
PKG_SYNC=""

PKG_TOOLS="patchelf i2c-tools evtest"

PKG_DEBUG="debug"

if [ "${BASE_ONLY}" = "true" ]
then
  EMULATION_DEVICE=no
  PKG_DEPENDS_TARGET+=" ${PKG_TOOLS} ${PKG_FONTS} misc-packages"
else
  PKG_DEPENDS_TARGET+=" ${PKG_TOOLS} ${PKG_FONTS} ${PKG_SOUND} ${PKG_SYNC} ${PKG_GRAPHICS} ${PKG_UI} ${PKG_UI_TOOLS} ${PKG_MULTIMEDIA} misc-packages"

  # glmark2 and vkmark (and the assimp vkmark pulls in, ~20 MB together) were
  # shipped in every image as benchmarks; nothing on the device uses them.

  # Sound support
  [ "${PIPEWIRE_SUPPORT}" = "yes" ] && PKG_DEPENDS_TARGET+=" alsa pipewire wireplumber"

fi

# Device is an emulation focused device
[ "${EMULATION_DEVICE}" = "yes" ] && PKG_DEPENDS_TARGET+=" emulators gamesupport"

# Add support for containers
[ "${CONTAINER_SUPPORT}" = "yes" ] && PKG_DEPENDS_TARGET+=" ${PKG_TOOLS} docker"

[ "${DEBUG_PACKAGES}" = "yes" ] && PKG_DEPENDS_TARGET+=" ${PKG_DEBUG}"

# 32Bit package support


# Automounter support
[ "${UDEVIL}" = "yes" ] && PKG_DEPENDS_TARGET+=" udevil"

# EXFAT support
[ "${EXFAT}" = "yes" ] && PKG_DEPENDS_TARGET+=" exfatprogs"

# NFS support
[ "${NFS_SUPPORT}" = "yes" ] && PKG_DEPENDS_TARGET+=" nfs-utils"

# Installer support
[ "${INSTALLER_SUPPORT}" = "yes" ] && PKG_DEPENDS_TARGET+=" installer"

# Devtools... (not for Release)
[ "${TESTING}" = "yes" ] && PKG_DEPENDS_TARGET+=" testing"

# OEM packages
[ "${OEM_SUPPORT}" = "yes" ] && PKG_DEPENDS_TARGET+=" oem"

# htop
[ "${HTOP_TOOL}" = "yes" ] && PKG_DEPENDS_TARGET+=" htop"

# modules packages
[ "${MODULES_PKG}" = "yes" ] && PKG_DEPENDS_TARGET+=" modules"

true
