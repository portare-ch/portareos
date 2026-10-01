<img src="distributions/PortareOS/logos/portareos-logo.png" width=320>

# PortareOS

**For Retroid Pocket Nova owners who care about every frame and millisecond.**

**[Home and installation guide](https://os.portare.org)** · [Known issues](BUGS.md) · [Roadmap](ROADMAP.md)

> Black coffee without sugar and milk. With the right amount of beans and water.

## What it is

PortareOS engineers the whole stack for low latency, consistent frame delivery
and faithful console timing on the Nova's 1280×960, 120 Hz panel. Kernel, emulators,
DSP topology, display driver, input path and frontend are all open to change.

Write the card, copy your games across, and play: one emulator per system,
with configs, scaling and shaders tuned for this device. Tweaking is not
expected. **Nova only, NTSC focused; PAL modes and other devices are not planned.**

## Status

PortareOS is in an early phase of development. For the sake of science,
things may break along the way.

| System | Emulator | Status |
| --- | --- | --- |
| Super Nintendo | Snes9x | ✅ Tested, full speed |
| PlayStation | SwanStation | ✅ Tested |
| PlayStation 2 | [ARMSX2 (libretro)](documentation/emulators/ARMSX2.md) | 🚧 Playable, optimization ongoing ([#477](https://github.com/portare-ch/portareos/issues/477)) |
| GameCube | Dolphin (libretro) | ❌ Currently broken: hangs, no sound ([#463](https://github.com/portare-ch/portareos/issues/463)) |

A linked emulator has its own page with what was measured and why it is set
up the way it is: [documentation/emulators/](documentation/emulators/README.md).

## Concepts

* **Hardware follows the console.** Custom panel modes and switchable audio
  clocks match the original systems instead of forcing every game into
  60 Hz and 48 kHz.
* **Less buffering, measured responsiveness.** Kernel audio changes reduce
  buffering and jitter; community testing reports steadier frame delivery
  and lower button-to-screen latency than Android. Audio latency remains
  somewhat higher.
* **Purpose-built system apps.** A direct-KMS launcher and small services
  handle networking, input and Bluetooth without a desktop.
* **Under 500 MB compressed.** One emulator per system, with configs,
  shaders and scaling tuned for this panel.
* **Measure, then change.** Panel timing, tearing and audio test tools guide
  the work, including experiments with the gamepad MCU and black frame insertion.

Everything that does not serve that is an anti-feature and comes out.

## What is different

Most distributions drive the panel at 60 or 120 Hz and the audio at 48 kHz,
and resample everything to fit. PortareOS changes the hardware to fit the
console instead.

### Panel modes matched to the console

The Nova has no variable refresh rate, so the panel driver carries one mode
per console family, at twice the console's frame rate. RetroArch asks for
the matching mode when a game starts, presents each frame once, timed to
the vblank two refreshes after the last, and the core is paced by the panel:
a frame lands on a frame, at the console's rate. The game keeps its own
timing instead of periodically dropping or repeating a frame to fit 60 Hz.
See [refresh rates](documentation/PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md)
for the implementation and measurements.

| Panel mode | Console | Frame rate |
| --- | --- | --- |
| 119.880 Hz | Dreamcast, PS2, PSP, GameCube, Xbox; default mode | 59.94 |
| 119.652 Hz | PlayStation, Nintendo 64, Saturn | 59.8261 |
| 119.455 Hz | Game Boy, Game Boy Color, Game Boy Advance | 59.7275 |
| 120.198 Hz | Super Nintendo, NES | 60.0988 |
| 119.846 Hz | Master System, Game Gear, Mega Drive, Mega CD | 59.9227 |
| 118.360 Hz | Neo Geo | 59.18 |
| 119.200 Hz | Neo Geo CD | 59.5999 |
| 120.000 Hz | Steam: PC games capped at 60 or 120 by a timer | 60 |

Console clocks determine these rates. SNES/NES also gets wider vertical
blanking for BFI experiments. The panel stays in its 120 Hz class.
SwanStation does not (yet) follow real PlayStation mid-game rate changes.

### Audio at the console's sample rate

The audio link follows the core's output at 48, 44.1 or 32 kHz. Kernel and
DSP changes let the hardware follow the stream; RetroArch selects the rate
whenever it opens the audio device.

| Link rate | Consoles |
| --- | --- |
| 44.1 kHz | PlayStation, Dreamcast, PSP, Neo Geo CD, every Sega system; N64 games at 22 or 44.1 kHz |
| 32 kHz | Super Nintendo; N64 games at 32 kHz |
| 48 kHz | PS2, Xbox, GameCube and Wii, and everything else |

N64 rates vary by game: the core reports the programmed rate and the device
reopens at the matching link rate. Resampling is avoided where hardware can
carry the rate; the SNES's exact 32040 Hz is unavailable. See
[audio sample rates](documentation/PER_DEVICE_DOCUMENTATION/SM8550/AUDIO_SAMPLE_RATES.md)
for hardware limits and emulator output rates.

### Lower audio latency

The audio work reaches into the kernel and Qualcomm DSP topology. Playback
uses **AudioReach shared-memory pull mode**, giving the driver a
sample-accurate position. The kernel no longer advertises
`SNDRV_PCM_INFO_BATCH` on this path, so PipeWire stops adding a period of
batch-device headroom. DSP periods now follow the stream's rate: 10 ms
instead of 480 frames, which previously meant 15 ms for SNES audio.

RetroArch now defaults to **8 ms**, down from the observed 32 ms crackle-free
floor. This setting is not end-to-end latency. Earlier camera tests already
showed improvement; further PCM period-floor experiments seek the hardware's
actual limit. See [audio latency](docs/audio-latency.md) for measurements.

### KMS, no compositor

Each program takes the panel itself:

* **The launcher** owns the panel through KMS with a CPU-written dumb buffer:
  no GPU rendering, just text on black.
* **RetroArch** renders with Vulkan straight to the display (`VK_KHR_display`).
* **mpv** plays films through Vulkan directly to the display, so a movie
  follows the same path as a game.
* **xemu and PortMaster** use SDL's KMS driver. They need no desktop to
  give them a window.
* **Steam** is the exception: it uses gamescope on the DRM backend.

There is no desktop compositor or EmulationStation in the image. Each
program controls presentation without another compositor's frame queue
between it and the panel.

### One emulator per system

One tool for the job, and the best one wins. Alternatives are removed
together with the settings nobody had tuned for them. See
[removed packages](documentation/REMOVED_PACKAGES.md) for what went and why.

| System | Emulator |
| --- | --- |
| Arcade, Neo Geo | FBNeo |
| Neo Geo CD | NeoCD |
| Game Boy, Game Boy Color | Gambatte |
| Game Boy Advance | mGBA |
| NES, Famicom, Famicom Disk System | Nestopia UE |
| Super Nintendo | Snes9x |
| Nintendo 64 | ParaLLEl N64 with ParaLLEl-RDP on Vulkan |
| GameCube, Wii | Dolphin |
| Master System, Game Gear, Mega Drive, Sega CD | Genesis Plus GX |
| 32X | PicoDrive |
| Dreamcast, NAOMI, Atomiswave | Flycast |
| PlayStation | SwanStation |
| Saturn | Beetle Saturn |
| PlayStation 2 | ARMSX2 |
| PSP | PPSSPP |
| Xbox | xemu |
| Point-and-click | ScummVM |
| Ports, PC | PortMaster, Steam |
| Movies, music | mpv, PORTAMP |

[Folders, formats and cores](documentation/PER_DEVICE_DOCUMENTATION/SM8550/SUPPORTED_EMULATORS_AND_CORES.md).
Compatibility and performance vary by game.

### Configured for this panel

* Integer scaling where console lines divide into 960: Game Boy at
  960×864, GBA at 5×, N64 at 2× on ParaLLEl-RDP, and PlayStation at 4×.
  LCD shaders serve Game Boy, GBC and GBA; PlayStation gets our CRT shader,
  and SNES uses crt-guest-advanced at an exact 4×. Where 224 lines leave
  32-pixel bars, they stay to preserve even scanlines.
* Correct palettes and boot logos, including GBC hardware and color correction
  for Game Boy Color games.
* Optional panel-wide sRGB/D65 color correction, using the display controller
  for games, films and the launcher. **Both profiles currently crush dark
  greys, so stock is the default** pending a refit. See
  [color profiles](documentation/PER_DEVICE_DOCUMENTATION/SM8550/COLOR_PROFILE.md).
* No automatic savestate loading.

### Movies at the right shape

mpv uses hardware H.264/HEVC decoding and direct Vulkan display output.
SD 4:3 rips with missing aspect flags regain their shape and get scanlines.
Playback position is saved on quit.

### Lightweight

The compressed image is now **under 500 MB**. Audio uses PipeWire, with a minimum
quantum of 256 frames (5.3 ms at 48 kHz). There is no artwork scraping,
media centre or file manager. Duplicate tools and wrappers are removed;
[the package inventory](documentation/PACKAGE_INVENTORY.md) records about
250 MB removed and roughly 130 MB still targeted.

### Latency

Latency takes priority after correctness: a 1000 Hz kernel tick, selectable
preemption, teo idle governor, schedutil with the chip's energy model,
swapchain sizes tuned per core, no threaded video, and automatic frame delay in
RetroArch. Panel timing was measured to better than one part per million
against the SoC clock. **Black frame insertion is work in progress.**

A community tester reports latency variation down to one frame, better
than Android, and button-to-screen latency about one frame lower. These
measurements describe the tested setup; the audio setting above is a
separate measure.

### Our system services and test tools

* **portarelauncher:** consoles, games and settings drawn directly through
  KMS, without a GPU-rendered desktop.
* **portnet:** a small C client using sd-bus and iwd replaces NetworkManager;
  iwd handles Wi-Fi and addressing. Existing saved networks migrate.
* **portsense:** replaces inputsense with device-specific C input handling.
* **Bluetooth agent:** our small C pairing and auto-connect daemon talks to
  BlueZ over sd-bus.
* **PORTAMP and sdl3text:** our music player and in-game text guide reader.
* **vblank-rate** measures actual panel timing; **tear-test** counts torn and
  dropped frames using DPU CRCs, with deliberate tearing to validate detection.
  **pcm-flags** reads driver flags and period constraints; **pcm-floor** streams
  at accepted periods and counts underruns. These join gdb and strace in
  unofficial debug builds.

### Device integration

Suspend/resume includes fixes for UFS, PCIe, Wi-Fi, the gamepad MCU and LEDs,
though overnight battery drain remains unresolved. microSD runs at UHS-I
SDR104, and the GPU can drop to 124.8 MHz for menus and films.

Charging mitigation reduces current as the battery warms; device verification
is pending. See [known issues](BUGS.md).

The **gamepad MCU reports every 5 ms (200 Hz)**, down from the vendor's
9 ms (111 Hz). `rsinput.frame_rate=3` sets the scan delay from boot and
restores it on resume; UART measurements confirmed 200 Hz across two
suspend/resume cycles ([#466](https://github.com/portare-ch/portareos/pull/466)).
At 250 Hz, about 19% of reports failed to reach evdev, so 200 Hz is the
default. Button-to-screen latency still needs measurement.

Several kernel patches came from
[pocknix-os](https://github.com/shuuri-labs/pocknix-os); their authorship is
preserved in each patch header.

## What it looks like

<img src="documentation/images/snes-super-mario-world.jpg" width="640" alt="Super Mario World on the Nova: scanlines from crt-guest-advanced at an exact 4x, with the 32-pixel bars">

**Super Mario World.** SNES timing at 120.198 Hz, exact 4× CRT scanlines
with 32-pixel bars, and a 32 kHz audio link.

<img src="documentation/images/movies-dvd-4-3.jpg" width="640" alt="A DVD rip playing in mpv, filling the 4:3 panel">

**A DVD rip.** Hardware decoding, direct display output, restored 4:3
aspect ratio and scanlines for standard definition.

<img src="documentation/images/launcher.jpg" width="640" alt="The launcher: a list of systems with game counts, and the volume, brightness, battery and time in the header">

**The launcher.** Text on black, drawn by the CPU into a KMS buffer. Systems
with games, the counts, and the four numbers that matter in the header.

## The rules

* **One device.** Every other device tree has been deleted, not switched off.
* **One emulator per system.** Redundancies are dropped.
* **KMS is the only way to launch a game.** No compositing, except for Steam.
* **The console's rates, not the display's.** Refresh and sample rates are
  matched wherever the hardware can carry them.
* **NTSC.** That is what is supported and cared for. PAL is not planned;
  fixes from contributors are welcome as long as they do not break NTSC.
* **Latency before everything except correctness.**
* **Anti-features come out.** If it is not needed for a smooth game, it is
  not in the image.

## Everyday use

[portarelauncher](https://github.com/portare-ch/portarelauncher) provides
consoles, games and settings for Wi-Fi, Bluetooth, SSH, USB gadget mode,
time zone and updates. Each device generates its own root password on first
boot, shown under About.

* **Home + Start** quits every emulator; **M1 + volume** adjusts brightness
  anywhere.
* **M2** in RetroArch opens a game guide: place a text file beside the ROM
  with its name and `.txt`. The game pauses; M2 or B returns to it.
* Settings > Consoles offers **PRMPT**, an experimental pre-emptive frame
  per 2D console. PlayStation keeps its measured, tuned configuration
  without this switch: the pre-emptive frame's performance cost was too high.
* PortMaster is its own platform, with controls matching the printed buttons.
* Updates download from GitHub over Wi-Fi through the launcher, using the
  nightly or release channel, and install on restart.

## Installing and current limitations

Installation steps are at **[os.portare.org](https://os.portare.org)**.
The first image requires a fresh card installation: PortareOS uses its own
boot partition label, so an in-place update over ROCKNIX will not find it.
Subsequent PortareOS updates work through the launcher.

PAL fixes are welcome if they preserve NTSC behaviour. The minimal interface
and one-emulator policy are deliberate choices. 16:9 systems (except PSP) are not supported.

Read [BUGS.md](BUGS.md) for observed problems and changes awaiting device
testing, including suspend battery drain and color profiles.
[ROADMAP.md](ROADMAP.md) covers upcoming work: black frame insertion,
suspend power, the SNES core choice and further footprint reductions.
BFI aims for CRT-like motion clarity by inserting black refreshes. It is
experimental and off by default; rolling bands and cadence stability remain
unresolved.

## Building

```
make docker-SM8550
```

Images are written to `target/`. The build wants a container runtime, roughly
100 GB of disk and several hours the first time through. The **Build**
workflow supports incremental builds. Kernel, Mesa, PipeWire and RetroArch
are kept current; a daily workflow opens pull requests for emulator updates.

## A note about AI

100% AI-assisted development, and I plan to keep it that way.

## Origin and licences

PortareOS began as a fork of [ROCKNIX](https://github.com/ROCKNIX/distribution),
itself a fork of [JELOS](https://github.com/JustEnoughLinuxOS/distribution),
and much of the engineering underneath is theirs. It no longer tracks ROCKNIX:
there is no merge and no import from upstream, and every package in the tree
is maintained here.
Please do not raise PortareOS problems with the ROCKNIX maintainers; for the
upstream project, go to [rocknix.org](https://rocknix.org).

PortareOS's own work is licensed under the
[GNU GPL Version 2](https://choosealicense.com/licenses/gpl-2.0/). Everything
inherited keeps its licence and its credit; see [LICENSE.md](LICENSE.md) and
the `licenses` folder.
