# PortareOS features

Built for the Retroid Pocket Nova, with low latency and faithful console timing
as priorities. One line per feature; implementation and device verification
vary. Experimental work and known limitations are listed separately below.

Reviewed 8 October 2026. See the [supported systems](../README.md#systems-and-status),
[verification inventory](FEATURES.md) and [known issues](../BUGS.md) for coverage
and test status.

## Device and performance

* Built exclusively for the Retroid Pocket Nova.
* Nova's own DSP and speaker-amplifier firmware replaces the Odin 2 firmware.
* 200 Hz gamepad reporting, up from the vendor's 111 Hz.
* Finer analog-stick reporting through a reduced MCU deadband.
* CPU isolation puts games on the performance cores and background services on the efficiency cores.
* Device interrupts and background kernel work stay on the efficiency cores during games.
* ARMSX2 threads are assigned individually to the X3 and A715 cores.
* Per-system and per-game CPU/GPU settings, restored after exiting.
* Latency-oriented kernel configuration with a 1000 Hz tick.
* Lightweight launcher renders without waking the GPU for its interface.
* Small native networking, input and Bluetooth services.
* UHS-I SDR104 microSD support.
* Automatic fan control.
* Suspend/resume fixes for storage, Wi-Fi, Bluetooth, controls and LEDs; overnight drain remains unresolved.
* Low GPU idle frequency and USB runtime power management.

Details: [CPU isolation](CPU_ISOLATION.md), [power measurements](POWER.md).

## Display and console timing

* Direct KMS presentation for emulators, without a desktop compositor.
* Automatic integer-multiple VRR for RetroArch on the built-in display.
* Variable refresh currently spans 80–120.198 Hz.
* Mesa repeats frames to keep lower frame rates within the panel's refresh range without rendering again.
* Dedicated fixed-refresh modes matched to console families.
* Corrected frame-rate calculations for NES, SNES, PlayStation, Saturn and N64.
* Timed Vulkan presentation and reduced frame buffering.
* Per-system integer scaling and aspect ratios tuned for the 1280×960 panel.
* CRT shaders configured for console games, including exact SNES scanline scaling.
* LCD shaders configured for Game Boy, Game Boy Color and GBA.
* Game Boy Color hardware mode and color correction.
* Hardware-accurate N64 graphics through ParaLLEl-RDP.

Details: [variable refresh](VARIABLE_REFRESH.md), [console timing](CONSOLE_CLOCKS.md),
[fixed-refresh modes](PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md).

## Audio

* PipeWire audio stack using Qualcomm AudioReach DSP playback.
* Shared-memory DSP playback with sample-accurate position reporting.
* Speaker and headphone links support 32, 44.1 and 48 kHz.
* RetroArch selects the audio output rate from the emulated core.
* Reduced audio buffering: 8 ms RetroArch setting and a configured 3 ms PipeWire minimum.
* DSP period lengths follow the sample rate, avoiding extra buffering at 32 kHz.

Details: [audio latency](../docs/audio-latency.md),
[sample rates](PER_DEVICE_DOCUMENTATION/SM8550/AUDIO_SAMPLE_RATES.md).

## Games and everyday use

* One selected emulator per system, with device-specific defaults.
* Global, per-system and per-game configuration overrides.
* PS2 blending accuracy automatically follows game-database recommendations.
* Saturn controls mapped to the original controller's two button rows.
* Home + Start quits games consistently.
* M1 + volume adjusts brightness throughout the system.
* M2 opens a text game guide beside the ROM and pauses RetroArch; returning to Vulkan cores needs further testing.
* Optional MangoHud performance overlay, toggled with L1 + Y.
* MangoHud measures frames reaching the display when presentation timing is available.
* Steam PC games through FEX and gamescope.
* Readable Steam Big Picture: a virtual 18-inch 4:3 display and default 1.6× interface scale fix tiny text on the Nova.
* Save states, fast-forward and configurable rewind in supporting RetroArch cores.
* Automatic save-state loading is disabled by default.

Details: [everyday controls](../README.md#installation-and-everyday-use),
[emulator notes](emulators/README.md).

## Launcher, connectivity and updates

* Minimal console-and-game launcher with battery, volume, brightness and time.
* English and Japanese interface.
* PS2-style rendering of Japanese kana and kanji.
* Japanese and accented game filenames display in either interface language.
* Favourites, recently played games and scrolling long titles.
* Optional PlayStation-style shape symbols for button hints.
* PortScope diagnostics for buttons, sticks, triggers and input report rate.
* Stick and trigger calibration with persistent settings.
* Integrated Wi-Fi, Bluetooth, SSH, language and time-zone settings.
* USB file transfer and USB networking modes.
* SFTP game transfer over the network.
* Unique root password generated for each device and displayed under About.
* Nightly and release updates downloaded through the launcher and installed on restart.
* Configurable charging indication through the stick LEDs.

Details: [installation and updates](INSTALLATION.md),
[launcher verification](FEATURES.md#launcher-and-system).

## Media

* Hardware-decoded H.264/HEVC video playback through mpv.
* Direct Vulkan video presentation.
* Saved movie playback position.
* Gamepad controls for seeking, chapters, subtitles and audio tracks.
* Restored 4:3 aspect for SD videos missing aspect metadata, with optional scanlines.
* PORTAMP music player with a Winamp-inspired interface, playlist and spectrum display.

Details: [screenshots](../README.md#what-it-looks-like),
[video controls](../packages/multimedia/mpv/config/input.conf).

## Debugging and measurement

* gdb captures thread backtraces; strace records system calls when a program hangs or fails.
* vblank-rate measures the panel's actual refresh rate and interval spread.
* vrr-probe tests panel modes, variable-refresh schedules and idle refresh behavior.
* present-probe sends known Vulkan frame schedules, including deliberately late frames.
* tear-test detects mixed scanout frames with DPU CRCs and validates detection by tearing on purpose.
* pcm-flags reports audio-driver capabilities and accepted period sizes.
* pcm-floor streams silence through the hardware PCM and counts underruns at each period size.
* perf-probe records game-run settings, clocks, temperature, battery charge and available frame-time logs.
* idle-probe measures idle battery power, interrupts, context switches and thread activity.
* coremap-check verifies PS2 thread placement and CPU isolation while a game runs.
* PortScope inspects controls and report rate, including the raw input path before InputPlumber.
* MangoHud exposes performance statistics and logs application and display frame intervals.
* Host-side display-trace captures display events over SSH; display-check checks the recording frame by frame.
* Host-side device-tests runs the automatic configuration checks from the device test plan.

The dedicated debug package is enabled by default in unofficial builds; the
guide distinguishes those tools from ordinary image utilities and host scripts.
See the [debug tools guide](DEBUG_TOOLS.md) for setup, commands and interpretation.

## Footprint and measurements

* Compressed image documented at under 500 MB; this is the download size, not installed storage usage.
* Duplicate tools and unused packages removed; further reductions are tracked in the package inventory.
* Lightweight launcher and services; a current RAM measurement is needed before quoting memory savings.

Image size should be rechecked against the release being downloaded. The 200 Hz
input rate and 8 ms audio setting are not end-to-end latency measurements.

Details: [package inventory](PACKAGE_INVENTORY.md), [audio measurements](../docs/audio-latency.md).

## Experimental and incomplete

* Preemptive frames and run-ahead: optional; compatibility and performance depend on the core.
* Black frame insertion: experimental, disabled by default, with unresolved visual issues.
* sRGB/D65 color profiles: implemented, but currently crush dark greys.
* Temperature-based charging-current reduction: implemented, awaiting device verification.
* External displays and display-audio routing: incomplete.
* Bluetooth audio: implemented, but compatibility with the latency tuning needs testing.
* GameCube/Wii: included, with known Dolphin failures.
* RetroAchievements and netplay: configuration support exists; coverage needs auditing, and PS2 lacks achievements.

Details: [known issues](../BUGS.md), [roadmap](../ROADMAP.md).
