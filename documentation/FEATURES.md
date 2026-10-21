# Features, as shipped

What PortareOS ships, one line each, with where it lives and whether a
device has confirmed it. This is the inventory the
test plan is written against: every row here gets a test, automatic on the
device where a script can read the answer, human where only eyes or ears
can. Configuration reviewed 21 October 2026. Verification records include
older builds; a row is not a new test of the current image.

Status: **verified** means someone ran it on a Nova and it did what the row
says; **partial** means some of it was seen; **unverified** means it has
only been built. See [known issues](../BUGS.md) and the [test plan](TEST_PLAN.md)
for outstanding checks. The device checker still has obsolete assertions;
see the test plan before interpreting its results.

## Display

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| One panel mode per console family | Fixed-refresh modes match console families; VRR uses the fastest 120.198 Hz mode for every core. Steam also uses that mode with VRR and a 60 fps ceiling. | kernel panel patches; `setsettings.sh`; gamescope patches | verified for recorded emulator/probe runs; final Steam game test pending | auto: live mode, frame rate and repeat trace; see VARIABLE_REFRESH.md |
| Steam Big Picture at 1.6 | gamescope reports a 4:3 18-inch display, 366x274 mm, four times the panel's 4.5, so Steam treats the panel as external with its scaling slider, and the scale is seeded at 1.6 into Steam's saved setting for that display: text the physical size of a Steam Deck's on the 91 mm panel. `steam.ui_scale` sets the seed; the slider under Settings > Display owns it afterwards. | `start_steam.sh` | verified | auto: `ThreadSetForceDeviceScaleFactors 1.000000 * 1.600000` in Steam's `console-linux.txt` |
| No vsync | RetroArch presents each frame when the core finishes it, and Sync to Exact Content Framerate times the loop at the core's own rate; on the variable refresh path the panel follows. A late frame is shown late instead of held a whole refresh. Without the timer, audio sync paced the loop and every game ran 0.4 to 0.5% fast. No setting turns vsync on: no key, no menu entry, no hotkey, not an override or a reset to defaults; xemu has it off too. | RetroArch patch 0021, `setsettings.sh` `set_vsync`, `xemu.toml` | verified: speed on Saturn and SNES, overrides and reset on the Nova | auto: `video_vsync = "false"` and `vrr_runloop_enable = "true"` in the launched config, frame rate equal to the core's; human: tearing and judder in a horizontal scroll |
| Timed presents on Vulkan display | Each frame presented once, at a time the driver keeps (`VK_GOOGLE_display_timing`). Counting refreshes with vsync on, two per frame, went with vsync (0021). | RetroArch patch 0014 | verified | human: 240 fps camera; auto: RetroArch statistics for dropped frames |
| Per-core swapchain, no threaded video | Two images by default, three for ParaLLEl N64 and Dolphin. | `setsettings.sh`, `retroarch.cfg` | verified as configured | auto: config values in the launched RetroArch |
| Automatic frame delay | Enabled only at fixed refresh without preemptive frames. VRR uses the timed-present scheduler and disables automatic frame delay. | `setsettings.sh`, RetroArch patches | verified for recorded paths | auto: launched configuration; human: frame delivery |
| Integer scaling per system | GB 960×864, N64 2× on ParaLLEl-RDP, PSX 4× with the 240-line CRT shader, GBA 5× under lcd-grid-v2, SNES 4× under crt-guest-advanced; 32-pixel bars kept where the lines do not divide. | `system.cfg`, per-core `.cfg` and `.opt` | verified | human: screenshot per system against the expected geometry |
| Color profile (Gamma 2.2, sRGB) | A matrix and output curve in the display controller correct the panel to sRGB and D65. | `config/color/*.profile`, launcher `color.c`, `kms.c` | partial: applies; crushes dark greys | human: 16-step grey ramp, saturated patches |
| Stock as the default profile | Both profiles crush greys, so nothing is applied unless chosen; a one-shot migration moves devices back. | `system.cfg`, `post-update` `colorprofile-stock` | unverified | auto: `display.colorprofile` after update; marker file |
| External monitor replaces the panel | While a monitor is connected to USB-C the panel's connector reads disconnected. New launches select the monitor; the launcher fits its 4:3 screen into the monitor's mode. Running games retain their original output until exit. | `external-display`, `99-external-display.rules`, launcher `kms.c`, `fit.c`; #710 | broader hotplug and emulator coverage pending | human: D11 |
| Adaptive-Sync over DisplayPort | Capable DP sinks get DPU AVR and integer-multiple repeats. The EDID minimum is raised to at least 65 Hz; the usable maximum depends on the sink and selected mode. Branch devices are excluded. DP output is at most 8 bpc. | kernel patches 1127–1129; #713, #714, #716 | partial: NeoCD 59.62 fps / 119.24 Hz on LG UltraGear+ with the #714 test kernel; later floor change unverified | auto+human: D12 |
| De-gamma stage through the LUTDMA | Kernel patches 1070/1071 drive the third color block so pippopapera's three-table profiles can be used as they were measured. | kernel patches, `make-igc-profile.py` | unverified, never run | human, with SSH open: the kernel alone, then a bind-mounted profile |
| 8bpc output dither | The DPU leaves output dithering off at 8bpc, so a colour profile's 10-bit result is truncated onto the panel; the Nova panel opts in to the static ordered dither matrix. | kernel patch 0049, `rpnova.dts` | unverified | human: 16-step grey ramp with a profile on; auto: property in the live device tree |
| Lowest GPU operating point | 124.8 MHz idle so a menu or film keeps the fan off. | device quirks | verified | auto: `devfreq` cur_freq at the launcher |

## Audio

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Link rate follows the stream | 48, 44.1 or 32 kHz on the I2S link, no resampling where the console's rate can be carried. | kernel patches 1052 to 1055, DSP topology, PipeWire `allowed-rates` | verified (44.1); 32 by ear | auto: `hw_params` rate per system; human: pitch check |
| RetroArch picks the output rate from the core | `audio_out_rate = 0`: the rate is chosen from the core's at every audio init, so N64 games at 22.05, 32 or 44.1 kHz each get a matching link. | RetroArch patch 0015 | unverified | auto: `[Audio] Output rate picked` log line and `hw_params` on an N64 game |
| Per-core output rates | 44.1 kHz overrides for PlayStation, Saturn, Dreamcast, PSP, Neo Geo CD and the Sega cores. Other cores use automatic selection: SNES/NES 32 kHz, MSU-1 enhanced audio and GB/GBC 44.1 kHz, GBA 48 kHz; N64 varies by game. | per-core `.cfg`, `retroarch.cfg` | fixed overrides verified; automatic selection needs wider coverage | auto: A1–A3, log and `hw_params` per system |
| PipeWire with a 3 ms quantum floor | Native PipeWire playback; 144-frame minimum at the 48 kHz reference rate, scaled by rate, without power-of-two rounding. PulseAudio compatibility is provided by pipewire-pulse. | PipeWire patch 002; RetroArch patch 0017 | verified in recorded 32/44.1/48 kHz sessions; wider coverage pending | auto: running sink quantum and xruns; see AUDIO_LATENCY.md |
| No display audio | DisplayPort is video only; connecting a monitor leaves sound on the local outputs. | no DisplayPort DAI link in the device tree, UCM patch 0006; #709 | configured; wider output tests pending | auto: no DisplayPort sink with a display plugged; human: local playback through D11 hotplug |

## Emulation

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Core options in one shipped file | `retroarch-core-options.cfg` holds every core's options and RetroArch reads it (`global_core_options`); `setsettings.sh` changes its keys in place. Dolphin at 2x; Flycast at 640x480 with per-pixel alpha sorting. | `retroarch.cfg`, `retroarch-core-options.cfg`, `setsettings.sh` | verified | auto: E11 |
| One emulator per system | The table in README. | `virtual/emulators` | verified | auto: each core file present, no second one |
| Preemptive frame per supported console (PRMPT) | One preemptive frame, enabled by default for Neo Geo CD; off for other systems. PlayStation offers the option with SwanStation patch 002 and higher CPU/GPU clocks. Explicit classic run-ahead takes precedence. VRR already disables automatic frame delay independently. | `setsettings.sh`, `runemu.sh`, launcher Settings > Consoles | cost measured on SNES, PlayStation and NeoCD; NeoCD pause/resume checked in Metal Slug 1/2 | auto: E2 config and deliberate failure; human: deterministic save/load, input and audio; latency traces in LATENCY.md |
| PlayStation frame delivery | Vulkan at 4x, preemptive frames off, two swapchain images. Historical fixed-mode Tekken 3 baseline: 59.8 fps with no missed-refresh-sized frame; later VRR and PRMPT measurements are in the emulator notes. | `setsettings.sh`, `retroarch-core-options.cfg` | verified for recorded builds/settings | auto: launched config; human: E3; see emulators/SwanStation.md and LATENCY.md |
| Game guide on M2 | `<rom>.txt` next to the ROM; M2 takes the display down, sdl3text shows it, M2 or B returns to the game where it was. | RetroArch patch 0016, `sdl3text`, `setsettings.sh` hotkeys | verified on a 2D core; Vulkan cores open | human: N64 and Dreamcast return cleanly |
| Common quit and brightness hotkeys | Home + Start quits every emulator; M1 with volume sets brightness anywhere. | `portareos-hotkey`, `portsense`, launcher | verified | human: each emulator quits; brightness steps |
| GBC hardware and palette for GBC games | Gambatte given the GBC model and its color correction. | `Gambatte/gbc.opt` | verified | human: a GBC game's colors |
| ScummVM as a libretro core | LITE build with our engine list, FluidLite synth, data bundle to the system directory. | `scummvm-lr` | unverified | human: a game starts, music plays |
| No automatic savestate load | Deliberate. | `setsettings.sh` | verified | auto: `savestate_auto_load = "false"` |
| Emulator pins bumped daily | A workflow opens or refreshes one rolling PR containing upstream commit-pin changes. | `bump-emulator-pins.yml` | verified | auto: the workflow runs |

## Launcher and system

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| portarelauncher | KMS launcher on a dumb buffer: consoles, games, Tools, Settings; VRR keeps each menu frame doubled on the built-in panel. | `ui/portarelauncher` 0.8.4 | navigation verified on earlier builds; VRR probe record in VARIABLE_REFRESH.md | human: navigation and game return; auto: DRM ownership and repeat cadence |
| Quick Access: Recently played, Favourites, scrolling titles | The last ten launches under their day, a favourites list toggled with the left face button, and a selected long title that scrolls to its end. | `ui/portarelauncher` 0.5.1 | unverified | human: play, mark, scroll; portarelauncher#42 |
| PortScope | Settings > Diagnostics: every button, stick and trigger as the kernel reports it, the report rate measured, the last two events. Holding SELECT switches to the MCU and gpio-keys as they are before InputPlumber, which is stopped while that layer is shown. Replaces the SDL gamepad tester. | `ui/portarelauncher` 0.6.0, `/usr/bin/portscope` | unverified | human: each control lights, SELECT held switches layers, Home + START leaves; auto: `inputplumber` active after leaving |
| Shape marks | With Button style set to Shapes, every hint, the Button style diagram and PortScope draw the face buttons as outlined triangle, square, circle and cross. | `ui/portarelauncher` 0.6.0 | unverified | human: Settings, a games list and the Wi-Fi keyboard in both styles |
| Japanese | The launcher in English or Japanese, under Settings > Language & region (`system.language`, en_US or ja_JP). Kana and kanji drawn as the PS2 drew its system font: Noto Sans CJK JP at 26 x 26 with 16 levels, scaled with bilinear filtering. Titles in Japanese or accented file names read in either language. | `ui/portarelauncher` 0.7.0, `/usr/share/portarelauncher/ja26.bin` | verified: switching and the font; the rest unverified | human: L11 |
| Settings: Wi-Fi, Bluetooth, SSH, USB gadget, buttons, color, profile, charging LED, language & region, about, power | Each writes system.cfg or acts directly. | launcher | verified except Consoles | human per row |
| Settings > Consoles | PRMPT per console: SNES, NES, PlayStation, Game Boy, Game Boy Color, Game Boy Advance, Genesis and Neo Geo CD. | launcher 0.8.3 | broader menu coverage pending; NeoCD default recorded | human: rows and text; auto: keys written to system.cfg |
| Updates from GitHub | Nightly or release channel over Wi-Fi, installed on restart. | launcher `update.c`, `portareos-update` | verified | human: an update round trip |
| Per-device root password on first boot | Shown under About. | `007-rootpw` | verified | auto: password file exists; human: SSH with it |
| One-shot migrations | `post-update` runs each once: cpugovernor, FpsLimit, ssh on, colorprofile stock. | `post-update` | verified for the first three | auto: marker directory after update |
| Charging LED | Yellow thumbsticks while charging, dark otherwise, switchable. | launcher, LED daemon | verified | human |
| Home + Start handled by the launcher for emulators that do not quit | The launcher closes what does not close itself. | launcher `quit.c` | verified | human |
| Stick resolution | The gamepad MCU reports a stick only after it moved `stick_deadband` ADC counts of ±1024; the vendor's 40 made 23 levels from centre to rail, 5 to 6 steps out of 255 on the pad Steam and RetroArch see. 8 on the kernel command line gives one-step resolution with one event in 5 s at rest. | `devices/SM8550/options`, kernel patches 1019/1079/1080 | verified | auto: `/sys/module/rsinput/parameters/stick_deadband` is 8; human: evtest shows consecutive right-stick values 1 apart |

## Power and hardware

| Feature | What it does | Where | Status | Test |
|---|---|---|---|---|
| Charge current throttle | Full current below 40 °C, then 3, 2, 1 A at 40, 42, 44 °C with 2 °C hysteresis. | kernel patch 0510, `charge-throttle` service | unverified | auto: `journalctl -u charge-throttle` and `current_now` while charging warm |
| Suspend and resume | CX, AOSS and DDR now reach platform sleep; 23 mA over ten minutes on nightly 20261018. Wi-Fi returned within a second in that run. | kernel patches 1114–1124 (#658), sleep hooks | verified for two recorded cycles; overnight/open-PCM/charger and output coverage pending | human: repeated cycles with controls and audio; auto: sleep ledger and SoC counters; see POWER.md |
| Fan control | `fancontrol` curve. | quirks `fancontrol` | verified | auto: fan state against temperature |
| Gamepad MCU and stick LED rails off in suspend | rsinput and the HTR3212 LED driver release `vdd_mcu_3v3` across suspend, so the rail switches off instead of feeding a quiesced MCU. | kernel patches 1014 and 0033, `qcs8550-ayn-common.dtsi` | unverified | auto: regulator users at idle, sticks and LEDs back after resume; human: overnight drain against #62 |
| microSD at SDR104 | UHS-I high speed. | kernel config | verified | auto: `/sys` bus speed |
| 1000 Hz tick, teo, schedutil with the energy model | Latency-oriented scheduler and idle choices. | kernel config, `008-perfmode` | verified as configured, not measured | auto: `scaling_governor`, `current_governor` |
| Optional debug tools | gdb, strace and display/audio probes default on for unofficial builds and off for official builds; `DEBUG_PACKAGES=yes` enables them explicitly. | `virtual/debug`, build options | configuration recorded; binary availability must be checked on the image under test | auto: P6, binaries match the build's `DEBUG_PACKAGES` selection |

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
