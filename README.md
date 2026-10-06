<img src="distributions/PortareOS/logos/portareos-logo.png" width="320" alt="PortareOS logo">

# PortareOS

**For Retroid Pocket Nova owners who care about every frame and millisecond.**

**[Home and installation guide](https://os.portare.org)** · [Known issues](BUGS.md) · [Roadmap](ROADMAP.md)

> Black coffee without sugar and milk. With the right amount of beans and water.

PortareOS tunes the whole stack for low latency, consistent frame delivery
and faithful console timing on the Nova's 1280×960, 120 Hz panel. Hardware
follows the console's refresh and audio rates wherever possible. Correctness
comes first, then latency; features that serve neither come out.

Write the card, copy your games across, and play. One emulator per system,
with configs, scaling and shaders tuned for this device; tweaking is not
expected. **Nova only, NTSC focused.** Other device trees have been deleted.
PAL is not planned, though fixes that preserve NTSC behaviour are welcome.
16:9 systems, except PSP, are not supported.

[Installation and use](#installation-and-everyday-use) · [Systems and status](#systems-and-status) · [Screenshots](#what-it-looks-like) · [Technical details](#design-and-performance) · [Building](#building)

## Installation and everyday use

Follow the **[installation guide](https://os.portare.org)**. The first image
requires a fresh card installation: PortareOS's own boot partition label
prevents in-place updates from ROCKNIX. Later updates download from GitHub
over Wi-Fi through the launcher, using the nightly or release channel, and
install on restart.

[portarelauncher](https://github.com/portare-ch/portarelauncher) provides
consoles, games and settings for Wi-Fi, Bluetooth, SSH, USB mode, time zone
and updates. Each device generates a root password on first boot, shown
under About.

* **Home + Start** quits every emulator; **M1 + volume** adjusts brightness
  anywhere.
* **M2** in RetroArch opens a game guide: place a text file beside the ROM
  with its name and `.txt`. The game pauses; M2 or B returns to it.
* **Settings > Consoles > PRMPT** enables an experimental pre-emptive frame
  per 2D console. PlayStation keeps its measured configuration without this
  switch because the performance cost was too high.

## Systems and status

**Early development: things may break.** Compatibility and performance vary
by game. Status notes below cover specific tests, not every included system.

| System | Emulator / player | Status notes |
| --- | --- | --- |
| Arcade, Neo Geo | FBNeo | — |
| Neo Geo CD | NeoCD | — |
| Game Boy, Game Boy Color | Gambatte | — |
| Game Boy Advance | mGBA | — |
| NES, Famicom, Famicom Disk System | MesenCE | — |
| Super Nintendo | Snes9x | ✅ Tested; bsnes was too costly |
| Nintendo 64 | ParaLLEl N64 with ParaLLEl-RDP on Vulkan | — |
| GameCube, Wii | Dolphin (libretro) | ❌ GameCube: hangs, no sound ([#463](https://github.com/portare-ch/portareos/issues/463)) |
| Master System, Game Gear, Mega Drive, Sega CD | Genesis Plus GX | — |
| 32X | PicoDrive | — |
| Dreamcast, NAOMI, Atomiswave | Flycast | — |
| PlayStation | [SwanStation](documentation/emulators/SwanStation.md) | ✅ Tested |
| Saturn | Ymir | — |
| PlayStation 2 | [ARMSX2 (libretro)](documentation/emulators/ARMSX2.md) | 🚧 Playable; optimization ongoing ([#477](https://github.com/portare-ch/portareos/issues/477)) |
| PSP | PPSSPP | — |
| Xbox | xemu | — |
| Point-and-click | ScummVM | — |
| PC (x86 through FEX) | Steam on gamescope | ✅ Tested 2026-10-05; details below |
| Movies, music | mpv, PORTAMP | — |

Steam launches from the launcher again ([#533](https://github.com/portare-ch/portareos/pull/533));
SUPERHOT runs with sound ([#535](https://github.com/portare-ch/portareos/pull/535),
[#536](https://github.com/portare-ch/portareos/pull/536)), and Big Picture uses
a readable 1.6 scale ([#534](https://github.com/portare-ch/portareos/pull/534)).

See [folders, formats and cores](documentation/PER_DEVICE_DOCUMENTATION/SM8550/SUPPORTED_EMULATORS_AND_CORES.md)
for game setup, [emulator notes](documentation/emulators/README.md) for
measurements and configuration decisions, and
[removed packages](documentation/REMOVED_PACKAGES.md) for alternatives dropped
along with their untuned settings.

[Known issues](BUGS.md) tracks observed problems and changes awaiting device
testing. The [roadmap](ROADMAP.md) covers black frame insertion, suspend
power, the SNES core choice and further footprint reductions.

## What it looks like

<img src="documentation/images/snes-super-mario-world.jpg" width="640" alt="Super Mario World on the Nova: scanlines from crt-guest-advanced at an exact 4x, with the 32-pixel bars">

**Super Mario World.** SNES timing at 120.198 Hz, exact 4× CRT scanlines
with 32-pixel bars, and a 32 kHz audio link.

<img src="documentation/images/movies-dvd-4-3.jpg" width="640" alt="A DVD rip playing in mpv, filling the 4:3 panel">

**A DVD rip.** Hardware H.264/HEVC decoding, direct Vulkan output, restored
4:3 aspect for SD rips missing aspect flags, and scanlines. Playback position
is saved on quit.

<img src="documentation/images/launcher.jpg" width="640" alt="The launcher: a list of systems with game counts, and the volume, brightness, battery and time in the header">

**The launcher.** Text on black: systems with games, game counts, volume,
brightness, battery and time.

## Design and performance

Kernel, emulators, DSP topology, display driver, input path and frontend are
all open to change. Measurements guide the work.

### Panel modes matched to the console

The Nova has no variable refresh rate. Its panel driver carries one mode
per console family at twice the console's frame rate. RetroArch selects
the mode and presents each frame once, at the vblank two refreshes after
the last. The panel paces the core, preserving console timing without
periodically dropping or repeating frames to fit 60 Hz.

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

Panel timing was measured to better than one part per million against the
SoC clock. SNES/NES gets wider vertical blanking for BFI experiments; the
panel stays in its 120 Hz class. SwanStation does not yet follow real
PlayStation mid-game rate changes. See
[refresh rates](documentation/PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md)
for implementation and measurements.

**Black frame insertion is experimental and off by default.** It aims for
CRT-like motion clarity by inserting black refreshes; rolling bands and
cadence stability remain unresolved.

### Audio at the console's sample rate

Kernel and DSP changes let the audio link follow the core's output at 48,
44.1 or 32 kHz. RetroArch selects the rate when opening the audio device.

| Link rate | Consoles |
| --- | --- |
| 44.1 kHz | PlayStation, Dreamcast, PSP, Neo Geo CD, every Sega system; N64 games at 22 or 44.1 kHz |
| 32 kHz | Super Nintendo; N64 games at 32 kHz |
| 48 kHz | PS2, Xbox, GameCube and Wii, and everything else |

N64 rates vary by game; the core reports the programmed rate and the device
reopens at the matching link rate. Resampling is avoided where hardware
supports the rate; the SNES's exact 32040 Hz is unavailable. See
[audio sample rates](documentation/PER_DEVICE_DOCUMENTATION/SM8550/AUDIO_SAMPLE_RATES.md)
for hardware limits and emulator output rates.

### Lower audio latency

**AudioReach shared-memory pull mode** gives the driver a sample-accurate
position. Removing `SNDRV_PCM_INFO_BATCH` stops PipeWire adding a period of
batch-device headroom. Qualcomm DSP periods follow the stream's rate:
10 ms instead of 480 frames, which previously meant 15 ms for SNES audio.
PortareOS configures PipeWire for a 3 ms graph quantum. Current PCM
measurements and the remaining latency budget are documented in
[audio latency](docs/audio-latency.md).

RetroArch defaults to **8 ms**, down from the observed 32 ms crackle-free
floor. This setting is not end-to-end latency. Camera tests showed
improvement, though audio latency remains somewhat higher than Android.

### Configured for this panel

* Integer scaling to fit the 960-line panel: Game Boy at 960×864, GBA at 5×,
  N64 at 2× on ParaLLEl-RDP, and PlayStation at 4×. Game Boy, GBC and GBA
  use LCD shaders; PlayStation uses our CRT shader. SNES uses
  crt-guest-advanced at exact 4×, keeping 32-pixel bars around 224 lines to
  preserve even scanlines.
* Correct palettes and boot logos, with GBC hardware and color correction
  for Game Boy Color.
* Optional sRGB/D65 color correction through the display controller applies
  to games, films and the launcher. **Both profiles crush dark greys, so
  stock remains the default** pending a refit. See
  [color profiles](documentation/PER_DEVICE_DOCUMENTATION/SM8550/COLOR_PROFILE.md).
* No automatic savestate loading.

### Latency and input

A 1000 Hz kernel tick, selectable preemption, teo idle governor, schedutil
with the chip's energy model, per-core swapchain sizes, no threaded video
and RetroArch's automatic frame delay reduce buffering and jitter.

A community tester reports latency variation down to one frame and
button-to-screen latency about one frame lower than Android. These results
describe the tested setup; they are separate from the audio setting above.

The **gamepad MCU reports every 5 ms (200 Hz)**, down from the vendor's
9 ms (111 Hz). `rsinput.frame_rate=3` sets the scan delay from boot and
restores it on resume; UART measurements confirmed 200 Hz across two
suspend/resume cycles ([#466](https://github.com/portare-ch/portareos/pull/466)).
At 250 Hz, about 19% of reports failed to reach evdev, so 200 Hz is the
default. The effect on button-to-screen latency still needs measurement.

### KMS, no desktop

Each program controls presentation directly, without a desktop compositor's
frame queue or EmulationStation:

* **portarelauncher:** KMS with a CPU-written dumb buffer; no GPU rendering.
* **RetroArch:** Vulkan direct display (`VK_KHR_display`).
* **mpv:** Vulkan direct display, the same path as games.
* **xemu:** SDL's KMS driver.
* **Steam:** the exception, using gamescope on the DRM backend.

Small services handle the rest:

* **portnet:** a C client using sd-bus and iwd replaces NetworkManager.
  iwd handles Wi-Fi and addressing; saved networks migrate.
* **portsense:** device-specific C input handling replaces inputsense.
* **Bluetooth agent:** a C pairing and auto-connect daemon using BlueZ over sd-bus.
* **PORTAMP and sdl3text:** music player and in-game text guide reader.

### Device integration

Suspend/resume fixes cover UFS, PCIe, Wi-Fi, the gamepad MCU and LEDs;
overnight battery drain remains unresolved. microSD runs at UHS-I SDR104,
and the GPU can drop to 124.8 MHz for menus and films. Charging mitigation
reduces current as the battery warms; device verification is pending.

### Image size

The compressed image is **under 500 MB**, without artwork scraping, a media
centre or a file manager. Duplicate tools and wrappers are removed;
[the package inventory](documentation/PACKAGE_INVENTORY.md) records about
250 MB removed and roughly 130 MB still targeted.

## Building

```sh
make docker-SM8550
```

Images are written to `target/`. The build wants a container runtime, roughly
100 GB of disk and several hours the first time through. The **Build**
workflow supports incremental builds. Kernel, Mesa, PipeWire and RetroArch
are kept current; a daily workflow opens pull requests for emulator updates.

Unofficial debug builds include gdb, strace and tools for measuring changes:

* **vblank-rate:** measures actual panel timing.
* **tear-test:** counts torn and dropped frames using DPU CRCs, with
  deliberate tearing to validate detection.
* **pcm-flags:** reads driver flags and period constraints.
* **pcm-floor:** streams at accepted periods and counts underruns.

Development is 100% AI-assisted, and I plan to keep it that way.

## Origin and licences

PortareOS began as a fork of [ROCKNIX](https://github.com/ROCKNIX/distribution),
itself a fork of [JELOS](https://github.com/JustEnoughLinuxOS/distribution).
Much of the underlying engineering is theirs. PortareOS no longer tracks
ROCKNIX: no merges or imports, and every package is maintained here. Please
raise PortareOS problems here; the upstream project is at
[rocknix.org](https://rocknix.org).

PortareOS's own work is licensed under the
[GNU GPL Version 2](https://choosealicense.com/licenses/gpl-2.0/). Everything
inherited keeps its licence and its credit; see [LICENSE.md](LICENSE.md) and
the `licenses` folder.
