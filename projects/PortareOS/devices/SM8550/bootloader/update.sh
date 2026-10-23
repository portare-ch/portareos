#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

[ -z "$SYSTEM_ROOT" ] && SYSTEM_ROOT=""
[ -z "$BOOT_ROOT" ] && BOOT_ROOT="/flash"
[ -z "$BOOT_PART" ] && BOOT_PART=$(df "$BOOT_ROOT" | tail -1 | awk {' print $1 '})

# identify the boot device
if [ -z "$BOOT_DISK" ]; then
  case $BOOT_PART in
    /dev/mmcblk*) BOOT_DISK=$(echo $BOOT_PART | sed -e "s,p[0-9]*,,g");;
  esac
fi

# mount $BOOT_ROOT rw
mount -o remount,rw $BOOT_ROOT

if [ -d "$SYSTEM_ROOT/usr/share/bootloader/portareos_abl" ]; then
  mkdir -p $BOOT_ROOT/portareos_abl
  echo "Updating PortareOS ABL on SD..."
  cp $SYSTEM_ROOT/usr/share/bootloader/portareos_abl/* $BOOT_ROOT/portareos_abl
fi

# The bootloader isn't updated with the system: it may be one the user
# chose, such as Portare BIOS, and an older ABL can't read the settings a
# newer one moved out of devinfo. updateabl flashes the bundled ABL when
# run by hand.

### REMOVE IN THE FUTURE ###
# cleanup old boot files
[ -d "$BOOT_ROOT/boot" ] && rm -rf "$BOOT_ROOT/boot"
[ -d "$BOOT_ROOT/EFI" ] && rm -rf "$BOOT_ROOT/EFI"
# end

# mount $BOOT_ROOT ro
sync
mount -o remount,ro $BOOT_ROOT

echo "UPDATE" > /storage/.boot.hint
