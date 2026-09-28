# What is in the image, and what should not be

An inventory of the packages in the PortareOS image, from the package definitions and checked against a device running build 20260925 (`d3fa9894`): the binaries, libraries and services present, their sizes, and who links what. Sizes are as installed: `/usr/lib` 732 MB, `/usr/share` 457 MB, `/usr/bin` 220 MB, about 1.4 GB in all. Each package is in one of three lists: essential, candidate for removal, questionable.

The rule this applies is the README's: if it is not needed for a smooth game, it is not in the image.

## Essential

| Package | Why |
|---|---|
| linux 7.2.5, linux-firmware, busybox, systemd, util-linux, coreutils, bash, kmod, udev | The base. |
| mesa (turnip, freedreno; `libgallium` 21 MB), vulkan-loader, libdrm, libglvnd | The display. |
| pipewire, wireplumber, alsa-lib, alsa-ucm-conf, alsa-topology-conf | Audio; the 32 / 44.1 / 48 kHz link runs through it. |
| networkmanager, iwd, wireless-regdb, openssh, rsync, bluez | Wi-Fi, SSH, controllers. |
| retroarch, core-info, slang-shaders (trimmed, see below), the 15 cores (193 MB) | The systems. |
| armsx2-sa, xemu-sa (19 MB), scummvm-lr, ppsspp-lr, mpv, ffmpeg, libplacebo, luajit | The standalone systems and the two large cores; mpv's Lua runs our seek script. |
| portarelauncher, portareos, system-utils, quirks, autostart, powerstate, sleep, inputplumber (10 MB) | Our own stack; inputplumber is the gamepad. |
| steam, gamescope, xwayland, seatd, fex-emu, pressure-vessel, the X11 libraries | The one compositor exception, about 35 MB on the image; the runtime lives on `/storage`. |
| retroarch-assets (33 MB) | RetroArch's own menu needs its assets. Trimmable to one menu driver's. |
| e2fsprogs, dosfstools, exfatprogs, parted, udevil, umtprd | Cards, drives, USB file transfer. |
| dbus, glib, openssl, gnutls, curl, wget, jq, xmlstarlet | What the scripts use. |

## Candidates for removal

| Package | MB | Why |
|---|---|---|
| **kernel-overlays** | 59 | Not what it looked like: 16 MB of modules, the rest the Nova's own firmware, already trimmed to this device's DSP, GPU, Wi-Fi and Bluetooth blobs. Nothing worth cutting. |
| **slang-shaders** — trim, not drop | 70 → ~10 | We use `crt/crt-guest-advanced`, `handheld/lcd-grid-v2` and our own `portare/`. Keep those families and what they include; drop the other 60 MB. |
| **renderdoc, apitrace (with glretrace, eglretrace), gdb, gdbserver, perf, vulkan-tools, glslc, binutils (strings, readelf), v4l-utils, edid-decode, cec-ctl, plplay, gltrim, wflinfo** | ~55 | Debugging and GPU tracing tools, in a release image. `DEBUG_PACKAGES` is off, so they arrive as somebody's dependency; find whose. |
| **gstreamer, gst-plugins-base, gst-plugins-good, gst-libav** | 8 | No binary links it. qt6 pulled it and is gone; portmaster still lists gst-plugins-base, for ports. Goes with portmaster. |
| The sqlite3 CLI, nano and dialog, bluez's btmon, two of p7zip's three binaries | ~4 | Duplicates and unused command-line tools. |
| **iwd_get-networks, ukify, spit** | – | Leftover scripts; the launcher uses nmcli. |
| **gconv** — trim to UTF-8 and Latin-1 | 19 | glibc's charset converters for every encoding there is. |
| **i18n** — trim to en_US | 13 | Locales for the world. |

## Questionable: replace, or reconsider

| Package | MB | The question |
|---|---|---|
| **python3** with pyudev, six, pyyaml, setuptools | 34 | Real users: `portareos-bluetooth-agent`, the pairing agent that runs as a service, and Steam's `steamdeps`. Rewrite the agent in C against bluez's D-Bus API, or as a bluetoothctl script, and Python goes. |
| **mangohud, mangoapp** | 12 | A performance overlay: handy for development, an anti-feature for a player. gamescope runs without it. |
| **scummvm-lr** | 77 | ScummVM as the libretro core, with the standalone's engines less ten that want a keyboard or carry nothing playable here. Every engine in the tree would be 120. |
| **fbneo** core | 76 | The largest core: every arcade driver. Fine for as long as arcade is a system. |
| **`/usr/lib/compat`**: libavcodec 58, librsvg, x265, aom, openssl 1.1, SDL2 | 41 | Old-ABI libraries for PortMaster ports: a second copy of ffmpeg and friends. Stays exactly as long as PortMaster does. |
| **portmaster** | – | Ports need the compat set above and their own launcher scripts. If ports are not a goal, it and the 41 MB leave together. |
| **umtprd** (MTP) beside the USB network gadget | – | Two USB file-transfer paths where one would do. |
| **btrfs-progs, libtirpc and rpcbind, heimdal** | ~10 | NFS is off in the options, but these came along as dependencies of something. Find whose. |

## Services that start at boot and deserve a look

`batteryledstatus` (idle unless `led.color=battery`), `hdmi-sense` (runs on a display plug; the sway-era `hdmi-hotplug` is gone), `debug-shell`, `debugconfig`.

## Removed

Done in #334, from the lists above:

| Package | MB | How |
|---|---|---|
| retropie-shaders (the `/usr/share/common-shaders` tree), the common-shaders and glsl-shaders lines for other boards | 22 | out of `virtual/emulators` |
| gtk3, with gdk-pixbuf, atk, at-spi2-core, pango and their tools | ~12 | xemu-sa listed gtk3 and atk for a display backend it does not use; libdecor built its GTK plugin. Both dropped, and the chain fell away. |
| espeak | 1 | `PKG_SOUND` emptied |
| entware | 1 | out of `virtual/image`, with the `/opt` link |
| btop | 1 | `BTOP_TOOL` gone from the options; htop stays |
| xorg-launch-helper, its `xorg.service`, xrandr | 1 | xwayland listed the helper, glew the CLI; neither needed them |
| the 310 `.info` files of cores we do not ship | 1 | `core-info` installs the fifteen we have, under their own names: Saturn's is `mednafen_saturn`, as the core file is, which the old rename to `beetle_` had broken |

Done in #351:

| Package | MB | How |
|---|---|---|
| rust, rustc-snapshot, rust-std-snapshot, cargo, cargo-snapshot, cbindgen, bindgen-cli | 0 | never in an image and no package built with them: Mesa has rusticl off and there is no NVK on an Adreno. Out of both trees with their update scripts. |
| libbluray, libaacs, libbdplus, libudfread, libdvdcss, libdvdread, libdvdnav, rtmpdump, zvbi, aom, libdvbpsi | 0 | no dependents anywhere; never built |
| libva, intel-vaapi-driver, media-driver, gmmlib, nvidia-vaapi-driver, nv-codec-headers, libva-utils, vadumpcaps | 0 | x86 and NVIDIA only; ffmpeg and mesa lose the VA-API branch that could not fire |
| rkmpp | 0 | Rockchip only; ffmpeg loses its `RK*` case |
| the root ffmpeg folder | 0 | shadowed by the project's package and never read |

gmu has gone: it was a second audio stack - SDL2, mpg123, vorbis, flac, opus - for the one job mpv already did through ffmpeg. PORTAMP is that mpv with a spectrum analyser for a picture and a player drawn around it, and adds no package. The GStreamer plugins, libmpeg2 and x264 stay, kept in reserve for playback; nothing links them today.

Done in #347:

| Package | MB | How |
|---|---|---|
| libretro-database, all but our systems | 95 | the package copies the cheat folders of the systems we build, 77 MB, instead of all 172 |
| tailscale, zerotier-one | 28 | out of the network metapackage and the options |
| retroarch-overlays and its overlay mount | 13 | out of the RetroArch set; RetroArch's overlay directory is `~/overlays`, for anyone's own |
| plplay | 0 | libplacebo's demo player, not built |
| usb-modeswitch | 1 | out of the image |
| bluez's meshctl and mesh-cfgclient | 1 | bluez built without mesh |
| apitrace, renderdoc, nvtop, memtester, valgrind, kmsxx, libva-utils | 0 | never in an image: the debug set is off for official builds, which the nightlies are. The set is gdb and strace now, 12 MB, in unofficial builds only. |
| v4l-utils | 3 | already gone from fresh builds since IR remote support went off (#422373c); the image on the device predates that |

Done in #335:

| Package | MB | How |
|---|---|---|
| scummvm as a standalone, fluidsynth and its service | ~10 | ScummVM is the libretro core now, with FluidLite inside it for MIDI; the soundfont stays. The standalone's 76 MB is replaced by the core's 77, with ten engines fewer. The saving is fluidsynth and the service. |
| qt6, and the CI job that built it | ~60 | ARMSX2 is built as upstream's SDL frontend, `armsx2-sdl`: VK_KHR_display to the panel, FullscreenUI for the menus, no window. Tested on the Nova before the switch. FEXConfig, a Qt desktop dialog, is not built. |

## The sum

Still on the table: slang-shaders ~60 + Python 34 + GStreamer 8 + locales and gconv ~25: **about 130 MB**, without touching a supported system. About 250 MB is out already (above); gdb and strace, 12 MB, come only with an unofficial build.

## Method

Package set: a walk of `PKG_DEPENDS_TARGET` from `virtual/image` through `packages/` and `projects/PortareOS/packages/` (project overrides winning), conditionals included. Ground truth: on the device, `ls -S /usr/bin`, `du -sm` over `/usr/lib` and `/usr/share`, `ldd` over every binary in `/usr/bin` to see who links GTK, GStreamer, Python, Qt and X11, the systemd unit list, and `command -v` for the tools in question.
