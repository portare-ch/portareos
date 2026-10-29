# Installing PortareOS

PortareOS supports only the **Retroid Pocket Nova**.

A first installation needs a **fresh PortareOS microSD image**. Moving from
ROCKNIX requires writing a fresh card; its image cannot be updated in place.

## 1. Download and verify

Choose a build from [GitHub releases](https://github.com/portare-ch/portareos/releases).
Download the Nova's `PortareOS-SM8550.aarch64-<date>.img.gz` and its matching
`.sha256` file. The `.img.gz` is for a fresh card; the `.tar` is for updates.

Keep both downloaded files in the same directory. From that directory,
verify the checksum, replacing `<date>` with the downloaded filename's date:

```sh
# macOS
shasum -a 256 -c 'PortareOS-SM8550.aarch64-<date>.img.gz.sha256'

# Linux
sha256sum -c 'PortareOS-SM8550.aarch64-<date>.img.gz.sha256'
```

Continue only if the check reports `OK`.

## 2. Write the card

Decompress the `.img.gz` and write the resulting `.img` to the microSD card
with a raw-image writer such as Raspberry Pi Imager or balenaEtcher. Select
the downloaded image and check the target card carefully: writing the image
erases that card. Eject it safely when writing and verification finish.

## 3. Boot the Nova

PortareOS bundles **[Portare BIOS](https://github.com/portare-ch/BIOS)**,
the Nova's bootloader, which replaces ROCKNIX's ABL. It is separate from
the emulator BIOS files stored under `/storage/roms/bios/`.

If Portare BIOS is already installed, power the Nova off, insert the card,
then hold **Volume Down** while powering on. Use the volume buttons to move
and Power to select. Open **Boot** and choose **PortareOS** on the **SD card**.
This boots the card once; **Boot order** chooses the default operating system.
By default, automatic Linux boot searches internal storage before the SD card.

### Install the bootloader first, if needed

Look in the `portareos_abl` folder on the card's FAT boot partition. If it
holds the Nova's `abl_signed-SM8550.elf` with Android backup, flash and
restore scripts, install from rooted Android:

1. Copy that folder to `/sdcard/portareos_abl` in Android's internal storage.
2. As root, run `sh /sdcard/portareos_abl/backup_abl.sh`. Keep copies of the
   resulting `abl_a.img` and `abl_b.img` on your computer before continuing.
3. As root, run `sh /sdcard/portareos_abl/flash_abl.sh` to write Portare BIOS
   to both bootloader slots, then power off and boot the card as above.

Alternatively, with ABL flashing unlocked, flash the bundled image from
fastboot on your computer. If the card's `portareos_abl` folder is missing
or empty, get `abl_signed-SM8550.elf` from the
[Portare BIOS releases](https://github.com/portare-ch/BIOS/releases):

```sh
fastboot flash abl_a abl_signed-SM8550.elf
fastboot flash abl_b abl_signed-SM8550.elf
fastboot reboot
```

Back up the existing bootloader before flashing. Flashing the wrong image
can leave the Nova unable to boot. The
[Nova EDL recovery kit](https://github.com/portare-ch/nova_recovery) provides
a recovery route even with a broken bootloader; its supplied backups restore
ROCKNIX's ABL, not Portare BIOS, and it includes no Android factory image.
Portare BIOS uses USB for fastboot and EDL; it does not boot from USB.
Its **Emergency download mode** menu item enters EDL after confirmation.
When off-mode charging is enabled, Portare BIOS has its own charging screen;
Power starts the default system and a volume key opens the boot menu.

### Install to internal storage

With the PortareOS SD card inserted, open Portare BIOS with **Volume Down**
at power-on and select **Install PortareOS**:

* **Dualboot** keeps Android. A first install shrinks Android's data
  partition to the size you choose and resets Android, so back up its data
  first. If PortareOS is already installed next to Android, this replaces
  only PortareOS's system and keeps its games, saves and settings.
* **Replace Android** removes Android and any existing internal PortareOS
  installation, giving PortareOS all of internal storage. Back up anything
  you want to keep from either system first.

Check the resulting space shown by the installer before confirming. Use
**Boot** to start the internal installation once, or **Boot order** to set
the default OS when Android is available. The SD card remains independently
bootable through the Boot list.

The distribution also ships `installtointernal`, an interactive shell script
run from PortareOS. Its first-install path wipes Android userdata and asks
for a new Android data size; it has no **Replace Android** mode. It can
replace an existing PortareOS or ROCKNIX installation, offering to keep or
wipe its storage. Use the Portare BIOS menu for the installation procedure
above; the script is a separate path with different prompts and behavior.

## 4. First boot and games

In the launcher, open **Settings > Wi-Fi** to join a network.
**Settings > About** shows the device's IP address and the root password
generated on first boot. Enable SSH in **Settings > SSH** if needed, then
connect with `ssh root@<address>` using that password.

### Game formats

**Use CHD for disc games. Cartridge games keep their native ROM formats**,
such as `.sfc`, `.nes`, `.gba` and `.z64`, or ZIP archives.
PlayStation, PlayStation 2, Dreamcast, Saturn, Sega CD and Neo Geo CD
accept only `.chd` images. All but Neo Geo CD also accept `.m3u`
playlists naming CHDs for multi-disc games. Xbox takes only CHDs made
from XISO images with `chdman createdvd`. PSP takes `.chd`, or `.pbp` for homebrew,
PSN titles and Minis. GameCube and Wii take `.rvz`, Dolphin's lossless
format, plus `.dol` homebrew and `.wad` channels. Copying an ISO, CSO,
CUE/BIN, GDI, GCZ or WBFS directly into the other disc systems' folders
will not make it appear in the launcher.

Each console has one folder, named for the US console: Mega Drive games
go in `genesis`, Super Famicom ones in `snes`, Famicom and Disk System
ones in `nes`, Mega-CD ones in `segacd`, and a hack goes in its console's
folder.

CHD compresses disc data losslessly and saves card space. Converting an
already lossy rip does not restore the original disc's quality. Cartridge,
arcade and floppy-disk games use their system's formats. GameCube and Wii
use RVZ rather than CHD because RVZ regenerates the discs' pseudo-random
padding and stores Wii data decrypted, which CHD cannot compress.

### Recommended: PortareOS tools and nova-push

Use **[PortareOS tools](https://github.com/portare-ch/portareos_tools)** on
your Mac or Linux computer to prepare and transfer games. `portare_chd.py`
converts discs locally; **nova-push** converts CUE, GDI and ISO inputs to
CHD, verifies the result, and transfers it over SSH with rsync. Existing
CHDs and cartridge ROMs can be transferred directly.

Follow the tools repository's dependency instructions. `nova-push` needs
Python 3.10 or newer, SSH and rsync; disc conversion also needs `chdman`,
and encoded CUE audio needs FFmpeg. The tools' installer installs `nova-push`
and `portare-chd`; alternatively, copy the standalone files to a directory
on your PATH and make them executable. Then, on your computer:

```sh
# Replace 192.0.2.1 with the address shown under Settings > About.
nova-push --set-host root@192.0.2.1
nova-push --list
nova-push psx "Game.cue"
nova-push ps2 "Game.iso"
nova-push dreamcast "Game.gdi"
nova-push neocd "Metal Slug.cue"
nova-push snes "Super Mario World.sfc"
```

For a disc with separate BIN or audio tracks, select its CUE or GDI
descriptor and keep its companion files beside it. The tools read them
during conversion; upload the resulting CHD. Source files are kept by
default. The tools support more systems than PortareOS includes, so use
`nova-push --list` to check the folders on your device.

Neo Geo CD uses the `neocd` system name. GameCube and Wii inputs can be
converted to RVZ during transfer with `dolphin-tool`; on macOS, convert in
Dolphin first and transfer the RVZ. See the tools' instructions for details.

Games belong under `/storage/roms/<system>/`, for example
`/storage/roms/snes/`. Required BIOS files belong under `/storage/roms/bios/`
in the layout expected by the emulator. An SFTP client can also connect
using the same address, `root` username and password to copy prepared games
and BIOS files. See
[game folders and supported formats](PER_DEVICE_DOCUMENTATION/SM8550/SUPPORTED_EMULATORS_AND_CORES.md)
for each system and the [README](../README.md#installation-and-everyday-use)
for controls and everyday use.

## Updating

In **Settings > About > Update**, choose the nightly or release channel,
download the update over Wi-Fi, and restart when the launcher says the
update is verified. It installs on restart.

For a manual update, download the PortareOS `.tar` and matching `.sha256`
from the same release. Verify it with `shasum -a 256 -c` on macOS or
`sha256sum -c` on Linux, as above. Copy the `.tar` to `/storage/.update/`
on the device, then restart. This is for an existing PortareOS installation
only; moving from ROCKNIX requires writing a fresh card.

PortareOS updates also flash the bundled Portare BIOS to `abl_a` and
`abl_b` when it differs. Updating the distribution can therefore replace
an older or custom bootloader.
