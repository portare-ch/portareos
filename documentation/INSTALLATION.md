# Installing PortareOS

PortareOS supports only the **Retroid Pocket Nova**. 

A first installation needs a **fresh PortareOS microSD image**. 
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

Copy your games into the appropriate folders under `/storage/roms/`, for
example `/storage/roms/snes/` for Super Nintendo. An SFTP client can connect
using the same address, `root` username and password. See
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
