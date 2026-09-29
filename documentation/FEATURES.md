# Features, as shipped

What PortareOS ships, one line each, with where it lives and whether a
device has confirmed it. This is the inventory the
test plan is written against: every row here gets a test, automatic on the
device where a script can read the answer, human where only eyes or ears
can. Last revised 27 September 2026, at nightly 155.

Status: **verified** means someone ran it on a Nova and it did what the row
says; **partial** means some of it was seen; **unverified** means it has
only been built. BUGS.md carries the check for each unverified row.

## Display

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| One panel mode per console family | The panel driver carries eight 120 Hz-class modes: seven each exactly twice a console's frame rate (119.880, 119.652, 119.455, 120.198, 119.846, 118.360, 119.200 Hz), and 120.000 Hz for Steam, for PC games that pace themselves at 60 or 120. RetroArch asks for the matching one at launch; gamescope takes 120.000. | kernel panel patches; `setsettings.sh` refresh table; RetroArch patch 0013 | verified | auto: `/sys/class/drm/*/modes` and RetroArch log per system |
| Timed presents on Vulkan display | Each frame presented once, timed to the vblank two refreshes after the last; core paced by the panel. | RetroArch patch 0014 | verified | human: 240 fps camera; auto: RetroArch statistics for dropped frames |
| Two-image swapchain, no threaded video | Shortest frame queue RetroArch allows. | `retroarch.cfg` | verified | auto: config values in the launched RetroArch |
| Automatic frame delay | RetroArch measures core time and delays input polling up to the slack. | `retroarch.cfg` | verified | auto: statistics overlay reports a non-zero delay |
| Integer scaling per system | GB 960×864, N64 2× on ParaLLEl-RDP, PSX 4× with the 240-line CRT shader, GBA 5× under lcd-grid-v2, SNES 4× under crt-guest-advanced; 32-pixel bars kept where the lines do not divide. | `system.cfg`, per-core `.cfg` and `.opt` | verified | human: screenshot per system against the expected geometry |
| Color profile (Gamma 2.2, sRGB) | A matrix and output curve in the display controller correct the panel to sRGB and D65. | `config/color/*.profile`, launcher `color.c`, `kms.c` | partial: applies; crushes dark greys | human: 16-step grey ramp, saturated patches |
| Stock as the default profile | Both profiles crush greys, so nothing is applied unless chosen; a one-shot migration moves devices back. | `system.cfg`, `post-update` `colorprofile-stock` | unverified | auto: `display.colorprofile` after update; marker file |
| De-gamma stage through the LUTDMA | Kernel patches 1070/1071 drive the third color block so pippopapera's three-table profiles can be used as they were measured. | kernel patches, `make-igc-profile.py` | unverified, never run | human, with SSH open: the kernel alone, then a bind-mounted profile |
| 8bpc output dither | The DPU leaves output dithering off at 8bpc, so a colour profile's 10-bit result is truncated onto the panel; the Nova panel opts in to the static ordered dither matrix. | kernel patch 0049, `rpnova.dts` | unverified | human: 16-step grey ramp with a profile on; auto: property in the live device tree |
| Lowest GPU operating point | 124.8 MHz idle so a menu or film keeps the fan off. | device quirks | verified | auto: `devfreq` cur_freq at the launcher |
| Black frame insertion | Planned, not shipped. | | not shipped | |

## Audio

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Link rate follows the stream | 48, 44.1 or 32 kHz on the I2S link, no resampling where the console's rate can be carried. | kernel patches 1052 to 1055, DSP topology, PipeWire `allowed-rates` | verified (44.1); 32 by ear | auto: `hw_params` rate per system; human: pitch check |
| RetroArch picks the output rate from the core | `audio_out_rate = 0`: the rate is chosen from the core's at every audio init, so N64 games at 22.05, 32 or 44.1 kHz each get a matching link. | RetroArch patch 0015 | unverified | auto: `[Audio] Output rate picked` log line and `hw_params` on an N64 game |
| Per-core output rates | 44.1 kHz for PlayStation, Saturn, Dreamcast, PSP, Neo Geo CD and the Sega cores through their own configs, SNES 32 kHz, the rest 48. | per-core `.cfg`, `retroarch.cfg` | verified | auto: `hw_params` per system |
| PipeWire only, 256-frame quantum | PulseAudio banned, CI fails if it returns; 5.3 ms minimum quantum. | `pipewire.conf`, CI check | verified | auto: `pw-top` quantum; no `pulseaudio` binary |
| HDMI audio sink switch | `hdmi_sense` moves the sound to a USB-C DisplayPort display when it is plugged, and back when it is pulled; plugged-in headphones win over the display. | `99-hdmi.rules`, `hdmi-sense.service`, `hdmi-headphones.service`, `hdmi_sense` | unverified sink match (BUGS) | human: plug HDMI, sound follows |

## Emulation

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Core options in one shipped file | `retroarch-core-options.cfg` holds every core's options and RetroArch reads it (`global_core_options`); `setsettings.sh` changes its keys in place. Dolphin at 2x; Flycast at 640x480 with per-pixel alpha sorting. | `retroarch.cfg`, `retroarch-core-options.cfg`, `setsettings.sh` | verified | auto: E11 |
| One emulator per system | The table in README. | `virtual/emulators` | verified | auto: each core file present, no second one |
| Preemptive frame per 2D console (PRMPT) | `<console>.preempt=1` gives one RetroArch preemptive frame, and turns off the automatic frame delay with it; classic run-ahead still available by count. Off by default on every console. Costs nothing measurable on SNES - all four runs delivered every frame - unlike the PlayStation, which is why that one has no switch. What it buys is unmeasured: a frame from the preemptive frame, most of a frame given back by losing the auto delay. It also asks the core to round-trip a savestate every frame, and "deterministic" is a claim in a metadata file rather than a proof, so a core that is not quite drifts rather than fails. | `setsettings.sh` `set_runahead`, `preempt_enabled`, launcher Settings > Consoles | cost verified on SNES; benefit unverified | auto: E2's keys, and the failure line forced to appear; human: no flicker on a press |
| PlayStation runs every frame on time | One configuration, no mode switch: Vulkan at 4x, preemptive frames off, two swapchain images, automatic frame delay on. Measured on Tekken 3 at mean 16.71 ms against a 16.715 ms target, 59.8 fps, no frame reaching the 25.07 ms a missed refresh costs. The preemptive frame was measured too and removed: 47.7 fps at two images, 59.8 with a third but p99 35 ms against 19.7, and the renderer made no difference to either. | `setsettings.sh`, `retroarch-core-options.cfg`, BUGS.md | verified | auto: core options and launched config; human: E3 frametime log |
| Game guide on M2 | `<rom>.txt` next to the ROM; M2 takes the display down, sdl3text shows it, M2 or B returns to the game where it was. | RetroArch patch 0016, `sdl3text`, `setsettings.sh` hotkeys | verified on a 2D core; Vulkan cores open | human: N64 and Dreamcast return cleanly |
| Common quit and brightness hotkeys | Home + Start quits every emulator; M1 with volume sets brightness anywhere. | `portareos-hotkey`, `portsense`, launcher | verified | human: each emulator quits; brightness steps |
| GBC hardware and palette for GBC games | Gambatte given the GBC model and its color correction. | `Gambatte/gbc.opt` | verified | human: a GBC game's colors |
| ScummVM as a libretro core | LITE build with our engine list, FluidLite synth, data bundle to the system directory. | `scummvm-lr` | unverified | human: a game starts, music plays |
| PortMaster as its own platform | Harbourmaster patch copies our control.txt and mapper; pad buttons as printed. | `portmaster` | unverified | human: install a port, buttons match printing |
| No automatic savestate load | Deliberate. | `setsettings.sh` | verified | auto: `savestate_auto_load = "false"` |
| Emulator pins bumped daily | A workflow opens a PR per upstream move. | `bump-emulator-pins.yml` | verified | auto: the workflow runs |

## Launcher and system

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| portarelauncher | KMS launcher on a dumb buffer: consoles, games, Tools, Settings. | `ui/portarelauncher` 0.2.8 | verified | human: navigation; auto: it holds DRM master at idle |
| Settings: Wi-Fi, Bluetooth, SSH, USB gadget, buttons, color, profile, charging LED, time zone, about, power | Each writes system.cfg or acts directly. | launcher | verified except Consoles | human per row |
| Settings > Consoles | PRMPT per 2D console, latency or visuals for PSX, with per-console text. | launcher 0.2.8 | unverified | human: rows and text; auto: keys written to system.cfg |
| Updates from GitHub | Nightly or release channel over Wi-Fi, installed on restart. | launcher `update.c`, `portareos-update` | verified | human: an update round trip |
| Per-device root password on first boot | Shown under About. | `007-rootpw` | verified | auto: password file exists; human: SSH with it |
| One-shot migrations | `post-update` runs each once: cpugovernor, FpsLimit, ssh on, colorprofile stock. | `post-update` | verified for the first three | auto: marker directory after update |
| Charging LED | Yellow thumbsticks while charging, switchable. | launcher, LED daemon | verified | human |
| Home + Start handled by the launcher for emulators that do not quit | The launcher closes what does not close itself. | launcher `quit.c` | verified | human |
| Stick and trigger calibration | Tools > Calibrate Gamepad (GPcal) measures centre, range and deadzone into rsinput's module parameters; Save writes an autostart script so it survives a reboot. | `gamepadcalibration`, `/storage/.config/autostart/GPcal.sh` | unverified; found the pad under the wrong name until nightly 156 | human: calibrate, reboot, sticks still centred; auto: parameters match the saved script |

## Power and hardware

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Charge current throttle | Full current below 40 °C, then 3, 2, 1 A at 40, 42, 44 °C with 2 °C hysteresis. | kernel patch 0510, `charge-throttle` service | unverified | auto: `journalctl -u charge-throttle` and `current_now` while charging warm |
| Suspend and resume | UFS, PCIe, Wi-Fi, gamepad MCU and LEDs survive suspend. | kernel patch stack, `009-sleepmode` | verified; overnight drain open (#62) | human: suspend, resume, everything back; auto: `current_now` in suspend |
| Fan control | `fancontrol` curve. | quirks `fancontrol` | verified | auto: fan state against temperature |
| Gamepad MCU and stick LED rails off in suspend | rsinput and the HTR3212 LED driver release `vdd_mcu_3v3` across suspend, so the rail switches off instead of feeding a quiesced MCU. | kernel patches 1014 and 0033, `qcs8550-ayn-common.dtsi` | unverified | auto: regulator users at idle, sticks and LEDs back after resume; human: overnight drain against #62 |
| microSD at SDR104 | UHS-I high speed. | kernel config | verified | auto: `/sys` bus speed |
| 1000 Hz tick, teo, schedutil with the energy model | Latency-oriented scheduler and idle choices. | kernel config, `008-perfmode` | verified as configured, not measured | auto: `scaling_governor`, `current_governor` |
| Debug tools only outside official releases | gdb, strace 7.2. | `virtual/debug`, `strace` | unverified (strace 7.2 build) | auto: binaries present in a nightly, absent in a release |

## Media

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| mpv direct to the display | Vulkan display output, hardware H.264 and HEVC decode, position saved on quit. | `mpv` config | verified | auto: decoder in use; human: playback |
| SD at 4:3 with scanlines | Rips that lost their aspect flag are shown at 4:3; SD gets scanlines. | `mpv` config | verified | human |

## Build and process

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Incremental nightly | Stages restore saved state and rebuild only what changed; a full rebuild on request. | workflows, `build-state.sh` | verified | auto: nightly duration |
| Thread logs in the job output | Failing stages print the named thread logs. | workflows | verified | auto |
| Package dependency check | Every dependency must resolve. | `check-package-deps.py`, CI | verified | auto |
| Commit linter | `package: text` titles, 72-column bodies. | `validate-commit` | verified | auto |
