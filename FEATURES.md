# Features

PortareOS is a Linux distribution for one device, the Retroid Pocket Nova.
Everything below exists because the Nova has a 1280x960 120 Hz panel and a
SM8550, and the whole image is tuned for that and nothing else.

Marked *untested* where nobody has confirmed it on hardware yet. The full
inventory, with a test for every row, is in
[documentation/FEATURES.md](documentation/FEATURES.md).

## Display

- **A panel mode per console** - seven 120 Hz-class modes, each exactly twice a console's frame rate, so a 60.0988 Hz SNES frame lands on two refreshes and nothing is dropped or repeated (plus 120.000 Hz for Steam).
- **The modes are exact** - measured against the SoC's own clock at better than a part per million, not assumed.
- **Timed presents** - each frame is presented once at the vblank it belongs to, so the core is paced by the panel rather than by a queue.
- **Shortest frame queue RetroArch allows** - two swapchain images, no threaded video, automatic frame delay on.
- **Integer scaling with real shaders** - SNES at an exact 4x under crt-guest-advanced, PlayStation at 4x with a CRT shader that draws one beam per console line, Game Boy Advance under an LCD subpixel grid.
- **A fitted colour profile** - the panel is wide-gamut and blue; the display controller's own colour blocks can correct it to sRGB and D65 for every game, film and menu *(off by default, both profiles still crush dark greys)*.
- **Black frame insertion** *(in progress)*.

## Audio

- **The link runs at the console's rate** - 32, 44.1 or 48 kHz, following the stream, so the SNES plays at 32 kHz and the PlayStation at 44.1 with no resampling stage invented for them.
- **8 ms audio latency** - as low as RetroArch allows; it was 32 before, and the DSP path is no longer what sets the floor.
- **The DSP takes 10 ms at every rate** - upstream fixed it at 480 frames, which is 10 ms only at 48 kHz and 15 at the SNES's 32.
- **Sample-accurate DSP position** - the playback graph uses the AudioReach endpoint that publishes its position, so nothing has to queue an extra period against a pointer that jumped.
- **PipeWire and nothing else** - PulseAudio is banned and CI fails the build if it returns.

## Emulation

- **One emulator per system** - the best one is picked and tuned, the rest are dropped along with the settings nobody maintained.
- **Every core's options in one file** - shipped, not accumulated per install.
- **The same hotkeys everywhere** - Home + Start quits any emulator, M1 with the volume keys sets brightness anywhere.
- **A game guide on M2** - a text file next to the ROM, shown over the paused game, back where you were on M2 or B.
- **Preemptive frames per 2D console** - RetroArch's cheaper run-ahead, switchable in Settings *(benefit untested)*.
- **No automatic savestate loading** - deliberate.
- **Emulator pins move daily** - a pull request a day to upstream heads.

## Launcher and system

- **portarelauncher** - consoles, games and settings, drawn straight to the panel with no compositor and no GPU.
- **Updates over Wi-Fi from GitHub** - nightly or release channel, installed on restart.
- **A per-device root password** - generated on first boot, shown under About.
- **Settings that change the machine** - Wi-Fi, Bluetooth, SSH, USB gadget mode, buttons, colour profile, charging LED, time zone.
- **portsense** - the buttons in one small daemon instead of an evtest per device piped through grep.

## Power and hardware

- **Real suspend** - UFS, PCIe, Wi-Fi, the gamepad MCU and the LEDs all survive it *(overnight drain still open)*.
- **Charging that eases off as the battery warms** - full current below 40 C, then 3, 2 and 1 A, the way Android's thermal mitigation does.
- **microSD at UHS-I SDR104**.
- **Latency tuning** - 1000 Hz tick, the teo idle governor, schedutil on the chip's energy model.
- **Stick and trigger calibration** *(untested)*.

## Media

- **mpv straight to the display** - H.264 and HEVC on the hardware decoder, a few percent of one core for 1080p.
- **4:3 rips shown at 4:3 again** - and standard definition gets scanlines, because a DVD was made for a CRT.

## Not in the image

No compositor, no EmulationStation, no artwork scraping, no media centre, no file
manager, no Qt, no PulseAudio. The image is about 470 MB compressed.

## What would help most

Anything on a system nobody has tried at the new audio latency, any emulator
that misbehaves after a suspend, and whether the colour profiles are usable on
a panel other than the one they were fitted against.
