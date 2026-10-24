# What is in the image, and what should not be

Package definitions reviewed 24 October 2026. The size audit was made on
build 20260925 (`d3fa9894`): `/usr/lib` 732 MB, `/usr/share` 457 MB,
`/usr/bin` 220 MB, about 1.4 GB installed. Those figures and the removal
estimates below are historical; they are not a measurement of the current
image. Current candidates are separated from the removal record.

The rule this applies is the README's: if it is not needed for a smooth game, it is not in the image.

## Essential

| Package | Why |
|---|---|
| linux 7.3, linux-firmware, busybox, systemd, util-linux, coreutils, bash, kmod, udev | The base. |
| mesa (turnip, freedreno; `libgallium` 21 MB), vulkan-loader, libdrm, libglvnd | The display. |
| pipewire, wireplumber, alsa-lib, alsa-ucm-conf, alsa-topology-conf | Audio; the 32 / 44.1 / 48 kHz link runs through it. |
| iwd, portnet, wireless-regdb, openssh, rsync, bluez | Wi-Fi, SSH, controllers. iwd does the 802.11 and the addressing; portnet is the command that drives it. |
| retroarch, core-info, slang-shaders, the 16 selected libretro cores | The systems. `slang-shaders` still installs the upstream set plus our presets; trimming is a candidate below. ARMSX2 ships its own info file; `core-info` supplies the other fifteen. |
| hakux-sa (6 MB), armsx2-lr, scummvm-lr, ppsspp-lr, mpv, ffmpeg, libplacebo, luajit | The standalone systems and the three large cores; mpv's Lua runs our seek script. |
| portarelauncher, portareos, system-utils, quirks, autostart, powerstate, sleep, inputplumber (10 MB) | Our own stack; inputplumber is the gamepad. |
| portareos-abl | Portare BIOS, bundled for initial bootloader installation and flashed to both ABL slots by updates. |
| steam, gamescope, xwayland, seatd, fex-emu, pressure-vessel, the X11 libraries | The one compositor exception, about 35 MB on the image; the runtime lives on `/storage`. |
| retroarch-assets (33 MB) | RetroArch's own menu needs its assets. Trimmable to one menu driver's. |
| e2fsprogs, dosfstools, exfatprogs, parted, udevil, umtprd | Cards, drives, USB file transfer. |
| dbus, glib, openssl, gnutls, curl, wget, jq, xmlstarlet | What the scripts use. |

## Candidates for removal

| Package | MB | Why |
|---|---|---|
| **kernel-overlays** | 59 | Not what it looked like: 16 MB of modules, the rest the Nova's own firmware, already trimmed to this device's DSP, GPU, Wi-Fi and Bluetooth blobs. Nothing worth cutting. |
| **slang-shaders** — trim, not drop | 70 → ~10 | We use `crt/crt-guest-advanced`, `handheld/lcd-grid-v2` and our own `portare/`. Keep those families and what they include; drop the other 60 MB. |
| Debugging and GPU tracing tools from the September audit | remeasure | The old ~55 MB estimate is not a current saving: unused recipes were removed, and the debug metapackage is opt-in for official images. Audit binaries and their dependencies on a current image before cutting more. |
| The sqlite3 CLI, nano and dialog, bluez's btmon | ~1 in the old audit | Recheck runtime and script users before removing. |
| **iwd_get-networks, ukify, spit** | remeasure | Old audit candidates; check whether each is installed and has a runtime caller on a current image. A source file alone does not establish image cost. |

## Questionable: replace, or reconsider

| Package | MB | The question |
|---|---|---|
| **Python3** and target Python modules | 34 in the old audit | The Bluetooth agent is already C. `gamecapture` is Python; the image still selects `six` and `pyudev`. Audit remaining runtime users and Steam's installed dependency scripts before proposing removal. Host-only Python build tools do not establish image cost. |
| **mangohud, mangoapp** | 12 in the old audit | MangoHud is an opt-in runtime overlay with PortareOS display-timing measurements. Check both gamescope and emulator users before removing either component. |
| **scummvm-lr** | 77 | ScummVM as the libretro core, with the standalone's engines less ten that want a keyboard or carry nothing playable here. Every engine in the tree would be 120. |
| **fbneo** core | 76 | The largest core: every arcade driver. Fine for as long as arcade is a system. |
| **umtprd** (MTP) beside the USB network gadget | – | Two USB file-transfer paths where one would do. |
| **libtirpc, heimdal, rpcbind** | 0 | Not an installed-size saving in the device audit; their unreachable recipes are now removed too. |

## Services that start at boot and deserve a look

`batteryledstatus` (idle unless `led.color=battery`), `debug-shell`, `debugconfig`. `input` runs `portsense`, which replaced a shell script that ran an evtest per device.

## Removal history

Sizes in this section describe the recorded removals, not a new inventory.
Later replacements are named where they would otherwise imply a component
still ships.

Done in #334, from the lists above:

| Package | MB | How |
|---|---|---|
| retropie-shaders (the `/usr/share/common-shaders` tree), the common-shaders and glsl-shaders lines for other boards | 22 | out of `virtual/emulators` |
| gtk3, with gdk-pixbuf, atk, at-spi2-core, pango and their tools | ~12 | xemu-sa, since replaced by hakux-sa, listed gtk3 and atk for a display backend it does not use; libdecor built its GTK plugin. Both dropped, and the chain fell away. |
| espeak | 1 | `PKG_SOUND` emptied |
| entware | 1 | out of `virtual/image`, with the `/opt` link |
| btop | 1 | `BTOP_TOOL` gone from the options; htop stays |
| xorg-launch-helper, its `xorg.service`, xrandr | 1 | xwayland listed the helper, glew the CLI; neither needed them |
| the 310 `.info` files of cores we do not ship | 1 | `core-info` installs the fifteen we have, under their own names: Saturn's was `mednafen_saturn`, as the core file was, which the old rename to `beetle_` had broken; it is `ymir` now |

Done in #351:

| Package | MB | How |
|---|---|---|
| rust, rustc-snapshot, rust-std-snapshot, cargo, cargo-snapshot, cbindgen, bindgen-cli | 0 | never in an image and no package built with them: Mesa has rusticl off and there is no NVK on an Adreno. Out of both trees with their update scripts. |
| libbluray, libaacs, libbdplus, libudfread, libdvdcss, libdvdread, libdvdnav, rtmpdump, zvbi, aom, libdvbpsi | 0 | no dependents anywhere; never built |
| libva, intel-vaapi-driver, media-driver, gmmlib, nvidia-vaapi-driver, nv-codec-headers, libva-utils, vadumpcaps | 0 | x86 and NVIDIA only; ffmpeg and mesa lose the VA-API branch that could not fire |
| rkmpp | 0 | Rockchip only; ffmpeg loses its `RK*` case |
| the root ffmpeg folder | 0 | shadowed by the project's package and never read |

gmu was replaced by PORTAMP, which uses mpv for playback and adds no
separate audio stack. GStreamer and its plugins, libmpeg2 and x264 were
initially kept in reserve; #701 later removed those unreachable recipes.

Done in #347:

| Package | MB | How |
|---|---|---|
| libretro-database, all but our systems | 95 | the package copies the cheat folders of the systems we build, 77 MB, instead of all 172 |
| tailscale, zerotier-one | 28 | out of the network metapackage and the options |
| retroarch-overlays and its overlay mount | 13 | out of the RetroArch set; RetroArch's overlay directory is `~/overlays`, for anyone's own |
| plplay | 0 | libplacebo's demo player, not built |
| usb-modeswitch | 1 | out of the image |
| bluez's meshctl and mesh-cfgclient | 1 | bluez built without mesh |
| apitrace, renderdoc, nvtop, memtester, valgrind, kmsxx, libva-utils | 0 | Not installed by the official build's debug set. The current eight-tool set is documented in [DEBUG_TOOLS.md](DEBUG_TOOLS.md); unofficial builds include it by default, and `DEBUG_PACKAGES=yes` enables it explicitly. The old 12 MB figure covered a smaller set. |
| v4l-utils | 3 | already gone from fresh builds since IR remote support went off (#422373c); the image on the device predates that |

Done in #335:

| Package | MB | How |
|---|---|---|
| scummvm as a standalone, fluidsynth and its service | ~10 | ScummVM is the libretro core now, with FluidLite inside it for MIDI; the soundfont stays. The standalone's 76 MB is replaced by the core's 77, with ten engines fewer. The saving is fluidsynth and the service. |
| qt6, and the CI job that built it | ~60 | ARMSX2 first moved to the SDL frontend, then to the current libretro core. Neither needs Qt. FEXConfig, a Qt desktop dialog, is not built. |

Done in #429:

| Package | MB | How |
|---|---|---|
| mkcontroller and its autostart | 0 | wrote 27 `DEVICE_BTN_*` variables nothing reads. `control-gen` stopped printing a `DEVICE` line, so the GUID was empty and every value came out blank; the only consumer anywhere is a template for standalone Mednafen, which is not installed. |
| six AYANEO and Thor inputplumber configs | 0 | other handhelds' input maps in a one-device tree. The Nova's was the file named `02-ayn-controller.yaml`. |

Done in #701: recipes no stage of the build reaches - toolchain, base,
either emulator stage, image or kernel. `genbuildplan.py` plans every stage
at `ae8b932a05` step for step the same without them. The image loses only
the installer's entry in `modules`, which pointed at a script it never
shipped.

| Package | MB | How |
|---|---|---|
| docker, moby, cli, containerd, runc, tini, docker-compose, ctop | 0 | `CONTAINER_SUPPORT` gone, with the Kodi-era docker addon template |
| nfs-utils, rpcbind, libnfs | 0 | `NFS_SUPPORT` gone; the kernel keeps `CONFIG_NFS_FS` off as before |
| openvpn, zerotier-one, tailscale | 0 | `OPENVPN_SUPPORT` and `ZEROTIER_SUPPORT` gone |
| lirc, libirman, eventlircd, ir-bpf-decoders, evrepeat, v4l-utils | 0 | `REMOTE_SUPPORT`, which nothing read any more |
| installer, oem, testing, driverselect, device-tree-overlays, tm16xx-display | 0 | their switches gone, and the `modules` entry that ran the installer |
| xorg-server, the xf86-video and xf86-input drivers, fluxbox, the X core fonts, xcb-util | 0 | Direct KMS is the normal path; Steam's gamescope keeps xwayland. |
| u-boot, atf, crust, rkbin, syslinux, grub, the Amlogic, Exynos and Raspberry Pi boot blobs | 0 | the Nova boots through ABL; Portare BIOS is now bundled as `portareos-abl` |
| gcc-aarch64, gcc-arm-none-eabi, gcc-bpf, gcc-or1k, the Linaro compilers, their binutils, go | 0 | cross compilers nothing builds with |
| mold | 0 | out of the linker choice with `MOLD_SUPPORT` |
| gstreamer and its plugins, libmpeg2, x264, x265 | 0 | the reserve #351 kept; nothing asked for it since |
| the rest | 0 | other boards' drivers (librga, generic-dsi, RTW88, nvidia), benchmarks and tracers (glmark2, vkmark, apitrace, renderdoc, valgrind), mesa's panfrost host build with libclc, libraries nothing links and Python build tools nothing builds with |

quilt stays: `tools/refresh-patches` builds it on demand. Twelve license
texts went with the recipes that were the only ones to declare them.

## The sum

The original estimates put shader trimming and Python at about 95 MB
combined. Python cannot be removed while retained tools need it, and the
shader closure still needs measurement and runtime tests. The recorded
locale, gconv, p7zip and btrfs-progs reductions were about 31 MB; see below.
Re-measure installed and compressed sizes on a current image before
publishing a new total. Removing recipes that were never installed reduces
maintenance, not image size.

## Method

Package set: a walk of `PKG_DEPENDS_TARGET` from `virtual/image` through `packages/` (then also `projects/PortareOS/packages/`, project overrides winning, before the two trees were folded into one), conditionals included. Ground truth: on the device, `ls -S /usr/bin`, `du -sm` over `/usr/lib` and `/usr/share`, `ldd` over every binary in `/usr/bin` to see who links GTK, GStreamer, Python, Qt and X11, the systemd unit list, and `command -v` for the tools in question.

## Trimmed in place

Not removals of a package, but of what a package installs.

| What | Was | Now | Kept |
|---|---|---|---|
| `gconv` | 19.2 MB, 257 modules | 1.2 MB, 13 | Latin-1 and -15, UTF-16/32, the Japanese encodings and libJIS. UTF-8 is inside glibc and needs no module. |
| `i18n/locales` | 12.1 MB, 369 | 4.1 MB, 19 | en_US and ja_JP, and the closure of what they copy and include - mostly `iso14651_t1_common` at 3.2 MB, which collation needs. |
| `p7zip` | 5.0 MB, 3 binaries | 1.1 MB, 1 | 7za, the standalone one. 7z needed `7z.so` and Codecs behind it; 7zr read only .7z. Nothing on the image called any of them. |
| `btrfs-progs` | 1.6 MB | gone | `CONFIG_BTRFS_FS` is off with it, asserted `=n` in `kernel_options`, so the device declines such a card rather than mounting one it cannot check. |
| btrfs and ntfs kernel drivers | - | gone | Asserted `=n` in `kernel_options`. Neither filesystem has a checker on the image any more - ntfs-3g went in #403 - so a card formatted either way is declined rather than mounted unrepairable. Cards arrive FAT32 or exFAT; internal storage is ext4. |
