<img src="distributions/PortareOS/logos/portareos-logo.png" width=320>

# PortareOS

**An opinionated Linux distribution for one device, the Retroid Pocket Nova.**

Home: **[os.portare.org](https://os.portare.org)**

> Black coffee without sugar and milk. With the right amount of beans and water.

## What it is

The Nova has a 1280×960 panel at 120 Hz. That is 4:3, the shape of everything
made before widescreen, and PortareOS exists to make the best possible
operating system for the best 4:3 handheld on earth. Write the card, copy the
games across, and every system is already set up for this panel, this gamepad
and this chip. Tweaking is not expected, and not encouraged.

Everything that does not serve that is an anti-feature and comes out.

## What is different

Most distributions drive the panel at 60 or 120 Hz and the audio at 48 kHz,
and resample everything to fit. PortareOS changes the hardware to fit the
console instead.

### Panel modes matched to the console

The Nova has no variable refresh rate, so the panel driver carries one mode
per console family, at exactly twice the console's frame rate. RetroArch asks
for the matching mode when a game starts, presents each frame once, timed to
the vblank two refreshes after the last, and the core is paced by the panel:
a frame lands on a frame, at the console's rate. How that works, and what
it took, is in
[REFRESH_RATES.md](documentation/PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md).

| Panel mode | Console | Frame rate |
| --- | --- | --- |
| 119.880 Hz | The 59.94 Hz consoles: Dreamcast, PS2, PSP, GameCube, Xbox; and the default | 59.94 |
| 119.652 Hz | PlayStation, Nintendo 64, Saturn | 59.8261 |
| 119.455 Hz | Game Boy, Game Boy Color, Game Boy Advance | 59.7275 |
| 120.198 Hz | Super Nintendo, NES | 60.0988 |
| 119.846 Hz | Master System, Game Gear, Mega Drive, Mega CD | 59.9227 |
| 118.360 Hz | Neo Geo | 59.18 |
| 119.200 Hz | Neo Geo CD | 59.5999 |

The rates come from the consoles' own clocks, and the modes only vary the
pixel clock, so the panel stays in its 120 Hz class throughout. They are
the NTSC rates: PortareOS is built for NTSC games and no PAL mode is
planned. Dynamic
switching mid-game was evaluated and dropped: SwanStation does not change
rate the way a real PlayStation does, so there is nothing to follow.

### Audio at the console's sample rate

The Nova's audio link runs at 48, 44.1 or 32 kHz, following the stream.
That took kernel patches (`1052` to `1055`) to unpin the DSP ports and derive
the I2S bit clock from the stream, an edit to the DSP topology, and a
RetroArch patch that picks the link rate from whatever the core produces,
every time the audio device opens:

| Link rate | Consoles |
| --- | --- |
| 44.1 kHz | PlayStation, Dreamcast, PSP, Neo Geo CD, every Sega system; N64 games at 22 or 44.1 kHz |
| 32 kHz | Super Nintendo; N64 games at 32 kHz |
| 48 kHz | PS2, Xbox, GameCube and Wii, and everything else |

The N64 is per game: each game programs its own rate, the core reports it
once the game has, and the device reopens at the matching link rate. No
resampling where the console's rate can be carried. An exact 32040 Hz, the
real SNES's, is not one the hardware can carry; the analysis is in
[AUDIO_SAMPLE_RATES.md](documentation/PER_DEVICE_DOCUMENTATION/SM8550/AUDIO_SAMPLE_RATES.md).
The full table, with every emulator's output rate, is in
[REFRESH_RATES.md](documentation/PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md).

### KMS, no compositor

Nothing draws through a compositor. Each program takes the panel itself:

* **The launcher** owns the panel through KMS with a dumb buffer. No GPU, no
  images, text on black.
* **RetroArch** renders with Vulkan straight to the display (`VK_KHR_display`).
* **ARMSX2** does the same, through a patch of ours: the renderer had a
  direct-to-display path that no frontend ever reached, and
  `001-vulkan-direct.patch` adds the branch that does. Qt runs offscreen and
  the GS takes the panel.
* **mpv** plays films through Vulkan direct to the display too, so a movie
  never passes through a compositor either.
* **xemu, PortMaster and Moonlight** run on SDL's KMS driver: there is no
  compositor in the image to give them a window.
* **Steam** is the one exception. It brings gamescope, its own compositor, on
  the DRM backend, because the Steam runtime cannot be recompiled.

sway and EmulationStation are gone from the image.

### One emulator per system

One tool for the job, and the best one wins. Where ROCKNIX shipped several
emulators for a platform, one was picked and the rest dropped, together with
the settings nobody had tuned for them.

| System | Emulator |
| --- | --- |
| Arcade, Neo Geo | FBNeo |
| Neo Geo CD | NeoCD |
| Game Boy, Game Boy Color | Gambatte |
| Game Boy Advance | mGBA |
| NES, Famicom, Famicom Disk System | Nestopia UE |
| Super Nintendo | Snes9x (bsnes still under evaluation) |
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
| Ports, streaming, PC | PortMaster (as a platform of its own, with the pad's buttons as printed), Moonlight, Steam |
| Movies, music | mpv, gmu |

Every emulator quits with the same buttons, Home + Start. M1 with the
volume keys sets the brightness, anywhere. Settings > Games offers each
2D system a choice of latency or visuals: latency runs the game one frame
ahead (RetroArch's preemptive frames) and keeps the CRT filter, visuals is
the picture as shipped. In RetroArch, M2 shows a game
guide: a text file next to the ROM with the ROM's name and `.txt`. The game
waits where it was, and M2 or B brings it back.

### Configured for this panel

* 4:3 with integer scaling where the console's lines divide into 960: Game
  Boy at 960×864, N64 at 2× on ParaLLEl-RDP, PlayStation at 4× with a CRT
  shader of our own that draws one beam per console line, the Game Boy
  Advance at 5× under an LCD subpixel grid (lcd-grid-v2), the Game Boy and
  Game Boy Color under their own LCD shaders, the SNES at an exact 4× with
  crt-guest-advanced. Where an integer scale leaves 32-pixel bars, they
  stay rather than stretch 224 lines over 960: even scanlines need it.
* Correct palettes and boot logos: a Game Boy Color game gets the GBC
  hardware and its color correction.
* A color profile for the panel. The Nova's screen is wide-gamut and
  blue-tinted; Settings > Color profile corrects it to sRGB and D65, at
  gamma 2.2 (the one for emulators) or the sRGB curve, in the display
  controller's own color blocks, so it holds for every game, film and the
  launcher. Fitted to pippopapera's colorimeter readings of this panel.
  Mainline drives two of the controller's three stages; our kernel drives
  the third, the de-gamma, and the profiles that use it follow their
  device test. See documentation/PER_DEVICE_DOCUMENTATION/SM8550/COLOR_PROFILE.md.
* No automatic savestate loading.

### Movies at the right shape

mpv is the video player. H.264 and HEVC decode on the Nova's hardware
decoder, a few percent of one core for a 1080p stream. Standard-definition
4:3 rips that lost their aspect flag are shown at 4:3 again, and SD gets
scanlines, because a DVD was made for a CRT. Position is saved on quit.

### Lightweight

* The image is about 540 MB compressed.
* PipeWire and nothing else. PulseAudio is banned, and a check in CI fails the
  build if it comes back. The graph's minimum quantum is 256 frames, 5.3 ms.
* No EmulationStation, no sway, no artwork scraping, no media centre, no file
  manager, no Qt: ARMSX2 runs as its SDL frontend.
* Wrappers and duplicate tools are removed as they are found. What is in the
  image, what has gone and what is still on the list is in
  [PACKAGE_INVENTORY.md](documentation/PACKAGE_INVENTORY.md): about 250 MB
  out so far, about 130 MB still to go.
* Debug tools, gdb and strace, come only in builds that are not official
  releases.

### Latency

1000 Hz tick, preemption model selectable at boot, the teo idle governor,
schedutil with the chip's energy model, and the emulator frame queue kept as
short as it goes: two swapchain images, no threaded video, each frame
presented once and timed to its vblank, and automatic frame delay in
RetroArch. Black frame insertion, which a 120 Hz panel showing 60 Hz content
can afford, is work in progress.

### Kept current

Kernel 7.2.5, Mesa 26.2.2, PipeWire 1.6.8 and RetroArch from a recent commit.
A daily pull request moves the emulators to their upstream heads.

### The launcher

[portarelauncher](https://github.com/portare-ch/portarelauncher) is the
front-end: consoles, games, and a settings menu with Wi-Fi, Bluetooth, SSH,
USB gadget mode, time zone, and updates. Updates come straight from GitHub
over Wi-Fi, from the nightly or the release channel, and install on restart.
Every device makes its own root password on first boot and shows it under
About.

### Tuned for the device

* Suspend, with a stack of kernel patches so UFS, PCIe, Wi-Fi, the gamepad
  MCU and the LEDs survive it.
* microSD at UHS-I SDR104.
* The lowest GPU operating point, 124.8 MHz, so a menu or a film keeps the
  fan off.
* Charging that eases off as the battery warms: full current below 40 °C,
  then 3, 2 and 1 A at 40, 42 and 44 °C, the way Android's thermal
  mitigation does, through a charger limit the kernel now exposes.

Several of the kernel patches behind these came from
[pocknix-os](https://github.com/shuuri-labs/pocknix-os); authorship is kept
in each patch header.

## What it looks like

<img src="documentation/images/snes-super-mario-world.jpg" width="640" alt="Super Mario World on the Nova: scanlines from crt-guest-advanced at an exact 4x, with the 32-pixel bars">

**Super Mario World.** The panel runs the SNES mode, 120.198 Hz, two
refreshes for every one of the game's 60.0988 frames, so nothing is dropped
or repeated. crt-guest-advanced draws the scanlines over an exact 4×; the
bars above and below are the price of even lines. The audio link is at
32 kHz, the console's own rate.

<img src="documentation/images/movies-dvd-4-3.jpg" width="640" alt="A DVD rip playing in mpv, filling the 4:3 panel">

**A DVD rip.** mpv decodes H.264 on the hardware decoder and draws straight
to the display, no compositor. The rip had lost its aspect flag; it is shown
at 4:3 again, filling the panel, with scanlines for standard definition.

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

## What is next

[ROADMAP.md](ROADMAP.md) is where this is going and
[BUGS.md](BUGS.md) is what is known to be broken or unfinished. Ongoing:
verifying today's changes on the device, suspend power, black frame
insertion, the SNES core choice, and the last 130 MB of footprint.

## Building

```
make docker-SM8550
```

Images are written to `target/`. The build wants a container runtime, roughly
100 GB of disk and several hours the first time through. The **Build**
workflow's `incremental` input restores per-stage state and skips packages
whose recipes have not changed.

## Installing

PortareOS uses its own boot partition label, so the first image must be
written to the card as a fresh install; an in-place update over a ROCKNIX
installation will not find its boot partition. Updates between PortareOS
builds work normally, from the launcher. Installation steps are at
[os.portare.org](https://os.portare.org).

## A note about AI

Yes, 100% and I plan to keep it that way.

## Origin and licences

PortareOS began as a fork of [ROCKNIX](https://github.com/ROCKNIX/distribution),
itself a fork of [JELOS](https://github.com/JustEnoughLinuxOS/distribution),
and much of the engineering underneath is theirs. It no longer tracks ROCKNIX:
there is no merge from upstream, and upstream packages come in one at a time.
Please do not raise PortareOS problems with the ROCKNIX maintainers; for the
upstream project, go to [rocknix.org](https://rocknix.org).

PortareOS's own work is licensed under the
[GNU GPL Version 2](https://choosealicense.com/licenses/gpl-2.0/). Everything
inherited keeps its licence and its credit; see [LICENSE.md](LICENSE.md) and
the `licenses` folder.
