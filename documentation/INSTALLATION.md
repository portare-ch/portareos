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

Power the Nova off, insert the card, then hold **Volume Down** while powering
on. In the boot menu, choose **Switch boot mode**, confirm with the power
button, then press power again to boot from the card.

If the device has no menu for switching boot mode, it needs a compatible
bootloader first. Follow the device-specific
[ROCKNIX Nova bootloader procedure](https://rocknix.org/devices/retroid/retroid-pocket-nova/#flashing-rocknix-abl),
including its backup step. Flashing the wrong bootloader can leave the
handheld unable to boot. Those instructions cover the bootloader; use a
PortareOS image for the operating system.

## 4. First boot and games

In the launcher, open **Settings > Wi-Fi** to join a network.
**Settings > About** shows the device's IP address and the root password
generated on first boot. Enable SSH in **Settings > SSH** if needed, then
connect with `ssh root@<address>` using that password.

### Game formats

**Use CHD for disc games. Cartridge games keep their native ROM formats**,
such as `.sfc`, `.nes`, `.gba` and `.z64`, or supported cartridge archives.
PlayStation, PlayStation 2, Dreamcast, Saturn and Neo Geo CD accept only
`.chd` images. All but Neo Geo CD also accept `.m3u` playlists naming CHDs
for multi-disc games. Copying an ISO, CUE/BIN or GDI directly into those folders
will not make it appear in the launcher.

CHD compresses disc data losslessly and saves card space. Converting an
already lossy rip does not restore the original disc's quality. Cartridge,
arcade and floppy-disk games use their system's formats. Experimental
GameCube/Wii and Xbox paths also retain emulator-specific formats because
their emulators do not accept CHD; consult the table below before preparing
those games.

### Recommended: PortareOS tools and nova-push

Use **[PortareOS tools](https://github.com/portare-ch/portareos_tools)** on
your Mac or Linux computer to prepare and transfer games. `portare_chd.py`
converts discs locally; **nova-push** converts CUE, GDI and ISO inputs to
CHD, verifies the result, and transfers it over SSH with rsync. Existing
CHDs and cartridge ROMs can be transferred directly.

Follow the tools repository's dependency instructions. `nova-push` needs
Python 3.10 or newer, SSH and rsync; disc conversion also needs `chdman`,
and encoded CUE audio needs FFmpeg. Copy the standalone `nova-push` file
to a directory on your PATH and make it executable. Then, on your computer:

```sh
# Replace 192.0.2.1 with the address shown under Settings > About.
nova-push --set-host root@192.0.2.1
nova-push --list
nova-push psx "Game.cue"
nova-push ps2 "Game.iso"
nova-push dreamcast "Game.gdi"
nova-push neocd "Metal_Slug.chd"
nova-push snes "Super Mario World.sfc"
```

For a disc with separate BIN or audio tracks, select its CUE or GDI
descriptor and keep its companion files beside it. The tools read them
during conversion; upload the resulting CHD. Source files are kept by
default. The tools support more systems than PortareOS includes, so use
`nova-push --list` to check the folders on your device.

For Neo Geo CD, convert locally with `portare_chd.py` first, then transfer
the CHD to `neocd` as above. The current nova-push automatic converter uses
the older `neogeocd` system name; that is not the device's folder name.

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
