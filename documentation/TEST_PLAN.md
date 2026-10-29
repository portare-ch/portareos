# Test plan

One test per row of FEATURES.md, on a Retroid Pocket Nova running the build
under test. Automatic tests are run by `tools/device-tests` over SSH and
print PASS, FAIL or SKIP per test; human tests are a checklist with the
exact thing to look or listen for. Configuration expectations reviewed
24 October 2026; recorded runs below include older builds.

`tools/device-tests` still contains obsolete assertions, including a fixed
256-frame audio quantum, automatic frame delay outside its current
conditions, and old PlayStation profile behavior. Its panel-mode checks
also need to distinguish fixed refresh from VRR. Keep its results, but
check those failures against the current configuration and the manual
procedures below before treating them as regressions. Updating the checker
is tracked in [known issues](../BUGS.md#build-and-configuration).

Test IDs follow the FEATURES.md groups: D display, A audio, E emulation,
L launcher and system, P power and hardware, M media, B build. A test is
`auto` when a command on the device reads the answer, `human` when only
eyes or ears can, and `auto+human` when a command confirms the setup and
a person confirms the effect.

## Running the automatic tests

```
tools/device-tests root@nova                    # idle checks
tools/device-tests root@nova game snes          # with a game of that system running
```

The first form checks the idle state: config files, sysfs, services. The
second form reads the state of the running emulator from
`/tmp/.retroarch.cfg` (the main `retroarch.cfg` for keys the launch does
not write), the RetroArch log and `hw_params`, so start a game of
the named system first and leave it running. Run it once per system in the
panel-mode table (gb, snes, nes, genesis, psx, n64, neogeo, neocd).

Results go into the Status column of FEATURES.md: a row is **verified**
once its auto test passes and its human test has been signed off on the
build named at the top of that file.

## Ground truth used by the tests

| Thing | Where it is on the device |
|---|---|
| Config RetroArch actually launched with | `/tmp/.retroarch.cfg` (what setsettings.sh changes for this launch) over `/storage/.config/retroarch/retroarch.cfg` |
| RetroArch log | `/storage/.config/retroarch/logs/` (newest file; `log_to_file` and verbosity on) |
| Emulator launch log | `/var/log/exec.log` |
| Boot log | `/var/log/boot.log` |
| Panel modes | `modetest -M msm -c` (mode list), `/sys/class/drm/card*-DSI-1/modes` |
| Vblank counter | `/sys/kernel/debug/dri/0/crtc-0/status` |
| Audio link rate | `/proc/asound/card0/pcm*p/sub0/hw_params` (`rate:` line) |
| PipeWire graph | `pw-dump`, `pw-top -b -n 1`, `wpctl status` |
| Settings | `/storage/.config/system/configs/system.cfg` |
| Migration markers | `/storage/.config/system/.migrations/` |
| Core options | `/storage/.config/retroarch/retroarch-core-options.cfg`; inspect the launched configuration for overrides |
| GPU frequency | `/sys/devices/platform/soc@0/3d00000.gpu/devfreq/3d00000.gpu/cur_freq` |
| Battery | `/sys/class/power_supply/battery/{temp,current_now,constant_charge_current,constant_charge_current_max,status}` |
| Fan | `$DEVICE_PWM_FAN` from `/etc/profile` (hwmon `pwm1`), `pwm1_enable` |
| Update stage | `/storage/.update/` |

## Display

### D1 One panel mode per console family (auto)

Idle: the DSI connector lists all eight modes.

```
grep -c . /sys/class/drm/card*-DSI-1/modes          # 8
modetest -M msm -c | grep -oE '[0-9]+\.[0-9]+' | sort -u
```
Expected refresh rates, to three decimals: 119.880, 119.653, 119.455,
120.198, 119.846, 118.360, 119.200, and 120.000.

With the default built-in-panel VRR path, every core uses the fastest
120.198 Hz mode. Check `video_refresh_rate`, the live CRTC state and a
display trace; the panel repeats frames at an integer multiple of the
core's rate. See [variable refresh](VARIABLE_REFRESH.md).

For a fixed-refresh comparison, save the current VRR setting, set the
tested system's `<system>.vrr=0` and relaunch. `video_refresh_rate` and
the Vulkan log should then name the table's mode. Restore the original
setting afterward.

| System (core) | Expected |
|---|---|
| gb, gbc, gba (gambatte, mgba) | 119.455 |
| snes, nes (snes9x, mesen2) | 120.198 |
| psx, n64, saturn | 119.653 |
| genesis (genesis_plus_gx) | 119.846 |
| neogeo (fbneo) | 118.360 |
| neocd | 119.200 |
| everything else | 119.880 |

Steam: gamescope selects the fastest mode that rounds to 120 Hz, currently
120.198 Hz, with adaptive sync and a 60 fps ceiling. Check live refreshes,
game rate and repeat cadence instead of expecting a constant 120.000 Hz.
Real-game validation of the final stack is still pending.

Fail if the selected mode disagrees with the path being tested, or a
fixed-refresh test falls back to the default for a system with its own row.

### D3 Per-core swapchain, no threaded video (auto)

Game running, in the launched config:

```
video_max_swapchain_images = "2"  # 3 for Dolphin
video_threaded = "false"
video_swap_interval = "0"      # RetroArch takes 1 under Sync to Exact Content Framerate
video_black_frame_insertion = "0"
video_vsync = "false"          # always: there is no vsync (0021)
vrr_runloop_enable = "true"    # always
```

The MangoHud frame rate over a minute is the core's own
rate within 0.01%: 59.826 for Saturn, 60.099 for SNES. Fail at 0.4% or more
above it, which is the loop running on audio sync alone.

### D4 Automatic frame delay (auto+human)

At fixed refresh without preemptive frames,
`video_frame_delay_auto = "true"` in the launched config. With VRR or
preemptive frames it must be `false`; VRR uses the timed-present scheduler
instead. Test each path explicitly. For the fixed-refresh path, enable
RetroArch's statistics and check frame delay after thirty seconds of play;
keep frame-delivery logs alongside the configuration.

### D5 Integer scaling per system (human)

Take a RetroArch screenshot in each system and measure the image in an
editor. The launcher has no screenshot tool.

| System | Expected picture |
|---|---|
| GB / GBC | 960×864, centred, black around |
| GBA | 1200×800 (5×), lcd-grid-v2 visible at 1:1 zoom |
| SNES | 1024×896 (4× of 256×224), crt-guest-advanced visible |
| NES | 4× of 256×240, 32-pixel bars top and bottom accepted |
| PSX | 4× internal, 240-line CRT shader, no half-pixel smear |
| N64 | 2× on ParaLLEl-RDP, no blur |

Fail if any edge shows a non-integer step (a row of pixels wider or
narrower than its neighbours).

### D6 Color profile Gamma 2.2 and sRGB (human)

Settings > Color profile: set each of sRGB and Gamma 2.2, then show a
16-step grey ramp image (opened directly with mpv over SSH) and
count the distinguishable steps at the dark end. Pass for a profile when all 16 are distinct and pure red, green and
blue patches do not shift hue against the stock profile. Known state:
both fail today on the dark steps; this test records how many steps
are lost.

### D7 Stock as the default profile (auto)

Idle, after an update from a build that had `gamma22` or `srgb` set (the
script skips the value check when system.cfg changed after the marker,
since the user may have picked a profile since):

```
grep ^display.colorprofile= /storage/.config/system/configs/system.cfg   # stock
ls /storage/.config/system/.migrations/colorprofile-stock                # exists
```
On a fresh install the key is `stock` too. Then set sRGB in the launcher,
reboot, and confirm the key stays `srgb`: the migration must run once.

### D8 De-gamma stage through the LUTDMA (human, SSH open)

Never run. Two stages, each with SSH connected before starting so a black
screen is recoverable:

1. Boot the kernel with patches 1070 and 1071 alone. The panel comes up,
   the launcher draws, `dmesg | grep -i lutdma` shows no errors.
2. Bind-mount a three-table profile from `make-igc-profile.py` over the
   active profile and select it. The picture changes; grey ramp as D6.

Fail at either stage on a black panel, a `dmesg` error from `dpu` or
`msm`, or a hang. Recovery: `reboot` over SSH.

### D9 Lowest GPU operating point (auto)

Idle at the launcher for thirty seconds:

```
cat /sys/devices/platform/soc@0/3d00000.gpu/devfreq/3d00000.gpu/cur_freq   # 124800000
cat .../min_freq                                                            # 124800000
```
Fan is off (`pwm1` reads 0) with the device below 40 °C.

### D10 8bpc output dither (auto+human)

Auto, idle: the panel node in the live device tree carries the opt-in.

```
ls /proc/device-tree/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0/armada,dpu-8bpc-dither
```
Human: the D6 grey ramp with sRGB or Gamma 2.2 selected. Pass when the
dark steps that were merged before nightly 156 are distinct, and a smooth
dark gradient (a night sky in any film) shows no bands. Compare the same
image with the stock profile: it must look the same as before, since
dithering an untouched 8-bit source changes nothing visible.

### D11 External monitor ownership and hotplug (auto+human)

These external-display procedures are not implemented in `tools/device-tests`.
Record the image, monitor, USB-C adapter, mode and emulator for each run.

- At the launcher, connect the monitor. `external-display connected` exits
  0, DP is connected and the panel connector reads disconnected. The launcher
  appears on the monitor with correct geometry.
- Launch a RetroArch game, hakuX, Steam and mpv in separate runs. Check DRM
  ownership, controls, aspect ratio, sound on the local outputs and return
  to the launcher. No DisplayPort audio sink should appear in `wpctl status`.
- Disconnect at the menu and confirm return to the panel. Repeat connection
  before boot and repeated plug/unplug cycles; inspect `dmesg` for USB oopses,
  DP timeouts and an interrupt storm, and check idle power after unplug.
- Test connection/disconnection during a game separately. A running game
  retains its launch output; record blanking, recovery on exit, hangs or
  reboots rather than treating menu handover as a game-hotplug pass.

### D12 DisplayPort Adaptive-Sync and 8 bpc (auto+human)

With an Adaptive-Sync display enabled in the monitor's own menu, check
`modetest -M msm -c` for `vrr_capable=1` and the effective range. For the
recorded LG UltraGear+ EDID (60–144 Hz), the current minimum should be
65 Hz. A higher EDID minimum must be preserved; branch devices and sinks
whose resulting range spans no more than 10 Hz must not qualify.

Confirm the live mode and at-most-8-bpc output in DRM state or the monitor's
diagnostics. Run NeoCD and SNES: the sink's refresh readout and a display
trace should show integer-multiple repeats near 119.2 and 120.2 Hz
respectively, with no flicker or loss of signal. Test lower content rates
and late frames with a probe before calling compensation verified. Repeat
with Adaptive-Sync disabled: `vrr_capable` should clear and fixed-refresh
playback must remain usable. Record monitor observations alongside the
controller trace; the latter alone does not establish displayed timing.

## Audio

### A1 Link rate follows the stream (auto+human)

Game running, per system:

```
grep rate: /proc/asound/card0/pcm*p/sub0/hw_params
```

The link runs at the rate RetroArch opened, the `at N Hz` of the
`Driver "pipewire" reports` line in the log. That rate is the per-core
`audio_out_rate` where A3 sets one, else A2's pick:

| System | Expected link rate |
|---|---|
| psx, saturn, dreamcast, psp, neocd, genesis, mastersystem, gamegear, segacd, sega32x | 44100 (per-core) |
| snes | 32000 (picked) |
| snes with an MSU-1 game's enhanced audio, nes | 44100, 32000 respectively (picked) |
| gb, gbc (32768 Hz) | 44100 (picked) |
| gba (65536 Hz) | 48000 (picked) |
| n64, scummvm and the rest | picked from the core's rate |

Human, for 32 kHz: play a SNES game with a known tune (Super Mario World
title) next to a recording; pitch and tempo match. A wrong link rate
gives a pitch shift of about a semitone.

### A2 RetroArch picks the output rate from the core (auto)

For any core without a per-core rate, the log's pick follows retroarch
patch 0015: the smallest of 32000, 44100, 48000 that the core's rate
divides into within 0.5 %, else the smallest above it, else 48000. The
script recomputes it from the core rate in the log. Start an N64 game at each of the three common rates (22.05 kHz: Super
Mario 64; 32 kHz: Ocarina of Time; 44.1 kHz: Perfect Dark). The RetroArch
log has one line per game

```
[Audio] Output rate picked for the core's 32006.00 Hz: 32000 Hz.
```
and `hw_params` matches the picked rate. `audio_out_rate = "0"` stays in
the launched config. Fail if every game picks 48000.

### A3 Per-core output rates (auto)

Covered by A1's table; additionally `audio_out_rate` in the per-core
config under `/storage/.config/retroarch/config/<core>/<core>.cfg` is
44100 for SwanStation, Ymir, Flycast, PPSSPP, NeoCD, Genesis
Plus GX and PicoDrive. The global file keeps `0`; without a per-core
override it picks 32000 for Snes9x's 32040 and 44100 for an MSU-1 game
with enhanced audio. NES picks 32000 and Gambatte's 32768 picks 44100.

### A4 PipeWire and the 3 ms quantum floor (auto+human)

```sh
command -v pulseaudio              # no separate PulseAudio server
pw-top                            # read the running sink, its rate and ERR
grep -E 'allowed-rates|min-quantum|power-of-two-quantum' /usr/share/pipewire/pipewire.conf
```

The graph permits 32, 44.1 and 48 kHz, with a 144-frame minimum at the
48 kHz reference rate and power-of-two rounding disabled. With an 8 ms
RetroArch request, its requested quantum is 96, 133 or 144 frames at the
three rates. Other clients can raise the running quantum. Test all three
rates, retain before/after ERR counters and listen for crackle. A follower's
QUANT column may show its request rather than the running sink's quantum.
See [audio latency](AUDIO_LATENCY.md) for measured limits and open coverage.

## Emulation

### E1 One emulator per system (auto)

```
ls /usr/lib/libretro/*_libretro.so
```
Exactly the cores in the README table, one per system; no alternative
Saturn core alongside `ymir`, for example. The
script carries the expected list.

### E2 Preemptive frame per 2D console (auto+human)

Auto, game running with `<system>.preempt=1` in system.cfg:

```
preemptive_frames_enable = "true"
run_ahead_enabled = "false"
run_ahead_frames = "1"
```
in `/tmp/.retroarch.cfg`, plus `video_frame_delay_auto = "false"`, which
the preemptive frame turns off. With `preempt=0` the first key is
`false`; automatic delay returns only at fixed refresh, since VRR disables
it independently.

The log has no `[Run-Ahead Preemptive]` line: RetroArch logs one only
when the preemptive frame fails. That absence is worth nothing until the
line has been seen, and `run_ahead_frames = "0"` makes `preempt_init`
return silently, so a config check alone cannot tell working from inert.
To make it fail on purpose, both steps are needed:

```
sed -i 's/"deterministic"/"basic"/' /tmp/cores/<core>_libretro.info
rm -f /tmp/cores/core_info.cache      # or the cache answers instead
```
and the launch then logs "Preemptive Frames unavailable because this
core lacks deterministic save state support". Note the info file
RetroArch reads is the one in `/tmp/cores`, not `/usr/lib/libretro`.

Human: hold the D-pad and tap jump repeatedly for a minute; no frame
flickers backwards and the sound does not stutter. Then set an explicit
`<system>.runahead=2` and confirm classic run-ahead
(`run_ahead_enabled = "true"`, `run_ahead_frames = "2"`).

Measured on SNES, Super Mario World, snes9x, with MangoHud as E3 sets it
up. The preemptive frame is free here: every run delivered every frame
the console asked for, and playing changed nothing that a second run of
the same setting would not.

| run | frames | expected | mean | p99 | max |
|---|---|---|---|---|---|
| idle, preempt=0 | 1802 | 1802.9 | 16.638 | 20.87 | 22.42 |
| idle, preempt=1 | 1802 | 1802.9 | 16.637 | 20.77 | 21.69 |
| playing, preempt=0 | 2704 | 2704.4 | 16.637 | 20.82 | 22.56 |
| playing, preempt=1 | 2704 | 2704.4 | 16.638 | 21.11 | 23.46 |

Target 16.639 ms, one refresh 8.32, so a missed refresh is 24.96 and
none of the four runs reached it. These are historical fixed-mode runs.
SwanStation's readback fix and later VRR changes have separate measurements
in [SwanStation](emulators/SwanStation.md) and [latency](LATENCY.md).

Preemptive frames remove one frame of the game's own lag. Physical
button-to-screen latency still needs a controlled trigger and camera test;
frametime logs alone do not establish that benefit. Neo Geo CD now enables
one preemptive frame by default, with Metal Slug 1/2 pause and resume
checks recorded; other systems keep it off. See [NeoCD](emulators/NeoCD.md).

### E3 PlayStation runs every frame on time (auto+human)

The PlayStation defaults to Vulkan at 4x, preemptive frames off and two
swapchain images. With VRR it uses the fastest 120.198 Hz mode and automatic
frame delay is off. Compare current delivery and latency with
[SwanStation](emulators/SwanStation.md) and [latency measurements](LATENCY.md).

Auto, after a PSX launch:

```
grep -E 'GPU_Renderer|GPU_ResolutionScale' \
  /storage/.config/retroarch/retroarch-core-options.cfg    # "Vulkan" and "4"
grep -E 'preemptive_frames_enable|video_frame_delay_auto|video_max_swapchain_images' \
  /tmp/.retroarch.cfg          # "false", "false", "2" with VRR
grep -E 'video_refresh_rate' /tmp/.retroarch.cfg           # about 120.198 with VRR
grep 'Timed presents' /storage/.config/retroarch/logs/retroarch.log
# One present per core frame, about 16.715 ms apart; no vsync counting.
```

The figures below are the historical fixed-mode baseline, before the
current VRR path. Compare them only with that configuration; they are not
absolute acceptance thresholds for VRR or every later core build.

With MangoHud logging on (`portareos.mangohud.enabled=1`, and
`output_folder`, `autostart_log`, `log_duration` in MangoHud.conf): play
Tekken 3 for the whole window. Against the 16.715 ms target the reference
run is mean 16.71, p95 18.23, p99 19.70, max 22.07, and 59.8 fps.

Three things make it a pass, and each fails differently:

* **The frame count.** Rows logged must be the window in seconds times
  59.826 - 1794 in 30 s. Fewer means frames were dropped, whatever the
  percentiles say.
* **No missed vblank.** No frametime at or above 25.07 ms, which is the
  target plus one refresh. The reference run's worst frame was 22.07.
* **The mean on target.** Within about 0.05 ms of 16.715, so cumulative
  drift over the run is nil.

Spread below 25.07 ms is the core finishing early or late against a
present deadline the swapchain absorbs; it does not reach the panel and
is not a failure. The figures above are MangoHud's frametime, now
`application_interval_ms`. `display_interval_ms` (#595) is when each frame
reached the panel: there a missed vblank is a frame of 25.07 ms or more,
and the spread is gone.

With PRMPT on (`psx.preempt=1`), mashing through a fight: the launched
config has `preemptive_frames_enable = "true"` and
`video_frame_delay_auto = "false"`, the CPU and GPU governors read
`performance` while the game runs, and the reference is 59.8 fps with
about 0.5 frames a second at or above 25.07 ms and p99 24.96. More than 2
a second means patch 002 or the clocks are not in effect.

### E4 Game guide on M2 (human)

Put `game.txt` beside `game.<ext>` for one game in each of: SNES
(snes9x), N64 (parallel_n64), Dreamcast (flycast). Start the game, press
M2: the text appears within a second, D-pad scrolls, M2 or B returns to
the game at the same frame with audio continuing. Repeat five times per
core. Fail on a black screen, a RetroArch restart, or a Vulkan error in
the log after return. N64 and Dreamcast are the open items.

### E5 Common quit and brightness hotkeys (human)

For every entry in the README table plus ScummVM and mpv: start
it, press Home + Start; it exits to the launcher within three seconds and
`/var/log/exec.log` ends with a clean exit line. Hold M1 and press volume
up or down: brightness steps visibly in every one of them.

### E6 GBC hardware and palette for GBC games (human)

Start a GBC-only game (Zelda: Oracle of Ages). Colours are the GBC's
desaturated set, not the pure ones; the RetroArch log shows Gambatte
loading `gbc.opt`. Start a GB game: the GB palette applies instead.

### E7 ScummVM as a libretro core (human)

Copy Beneath a Steel Sky (freeware) to roms/scummvm. Use Tools > Start
ScummVM to add the game's directory; its Tools > Playlist Generator creates
the `.scummvm` file the launcher needs. Launch that entry: the intro plays,
music sounds and a save and load cycle works. Check FluidLite separately
with a game configured for General MIDI.
`ls /storage/roms/bios/scummvm` holds the data bundle.

### E9 No automatic savestate load (auto)

Game running: `savestate_auto_load = "false"` in `/tmp/.retroarch.cfg`.

### E10 Emulator pins bumped daily (auto, GitHub)

Actions > bump-emulator-pins has a run for each of the last three days and
a PR exists for any pin that moved. Checked from the repository, not the
device.

### E11 Core options from the shipped file (auto)

Auto, idle: `retroarch.cfg` has `global_core_options = "true"`, so every
core reads `retroarch-core-options.cfg` and no per-core `.opt`. With a
GameCube game running, Dolphin's geometry is 1280x1056, the shipped 2x;
a per-core file would give the core's own 1x, 640x528.

## Launcher and system

### L1 portarelauncher (auto+human)

Auto, idle:

```
pgrep -x portarelauncher
pidof portarelauncher                   # busybox pgrep -x misses it
cat /sys/kernel/debug/dri/0/clients     # the launcher holds master
```
Human: browse consoles, games, Tools, Settings; each list scrolls,
selection wraps, back returns one level. Start and quit a game; the
launcher returns to the game that was started.

### L2 Settings rows (human)

Each row once. Wi-Fi off and on reconnects; Bluetooth pairs a pad; SSH off
then on (`ssh.enabled` follows, `sshd` stops and starts); USB gadget
mounts on a PC; buttons swaps A/B in the launcher; color as D6; profile
changes the CPU governor; charging LED as L7; Language & time as L11,
its time zone changing the clock under About and the Wi-Fi country
(`iw reg get`: Europe/Berlin is DE, UTC is 00); About shows version,
password and IP; power reboots and shuts down.

### L3 Settings > Consoles (auto+human)

Human: the row reads `defaults` until something is changed, then
`N changed`. Each 2D console toggles `PRMPT on`/`PRMPT off` with its
description; PlayStation also toggles PRMPT, off by default, and Neo Geo CD
starts on by default. No text runs off the 53-column grid. Auto after the
changes:

```
grep -E '^(gb|gbc|gba|nes|snes|genesis|psx|neocd)\.preempt=' /storage/.config/system/configs/system.cfg
```
matches what was set.

### L4 Updates from GitHub (human)

Settings > About > Update on the nightly channel: the newest nightly
downloads to `/storage/.update/`, the sha256 check passes, the device reboots into it
and About shows the new version. User settings in `system.cfg` survive
except for explicit migrations; managed RetroArch defaults are refreshed.
`.migrations` gains any new marker.

### L5 Per-device root password on first boot (auto+human)

Auto: `root.password` in system.cfg is twelve characters from the
no-lookalike alphabet and is neither `portareos` nor `rocknix`. Human: the
password under About logs in over SSH, and `portareos` does not.

### L6 One-shot migrations (auto)

```
ls /storage/.config/system/.migrations/
# cpugovernor-schedutil es-fpslimit ssh-default-on colorprofile-stock
```
Set `ssh.enabled=0`, reboot: it stays 0 (the migration is not re-run).

### L7 Charging LED (human)

`led.charging=1`: plug the charger, both sticks glow yellow within three
seconds; unplug, they go dark - the sticks are an indicator while this is
on, so an rgb colour does not come back. Set it off in Settings: no glow
on plug, and the colour from `led.color` returns. With `led.color=battery`
the battery service keeps the sticks either way.

Reboot with the charger already plugged and check the sticks are yellow
within a few seconds: the service used to lose a race with the battery
appearing and die for the session (#446).

### L8 Home + Start for emulators that do not quit (human)

Start mpv (it has no hotkey of its own); Home + Start returns to the
launcher within three seconds.

### L9 A saved stick calibration (auto)

GPcal is gone, but a calibration saved with it still runs at boot from
`/storage/.config/autostart/GPcal.sh`. Where one exists:

```
grep -o 'echo [-0-9]* > [^ ]*' /storage/.config/autostart/GPcal.sh | \
  while read -r _ v _ f; do [ "$(cat $f)" = "$v" ] || echo "MISMATCH $f"; done
```
No line printed means the live parameters are the saved ones.

### L10 PortScope (auto+human)

Human: Settings > Diagnostics > PortScope. Every button, the D-pad, both
triggers and both stick clicks light while held; each stick's dot follows
it and reads about +1.00 and -1.00 at the rails; `RATE` shows a number
while a stick moves and `--` a second after. Hold SELECT for a second:
the header says `PortScope, raw` and the same controls light from the
MCU; hold it again to go back. Home + START leaves, from either layer.
With Button style set to Shapes, the face buttons are outlined marks
here, in every hint line and in the Button style diagram. Auto, after
leaving from the raw layer:

```
systemctl is-active inputplumber       # active
grep -l DualSense /sys/class/input/event*/device/name   # the virtual pad is back
```

### L11 Japanese (auto+human)

Human: Settings > Language & time, press A on `Language / 言語`: every
screen redraws in Japanese, and again in English on the next press; a
restart keeps the choice. In Japanese: the console names are the ones
sold in Japan (スーパーファミコン, NINTENDO64); a ROM named in Japanese
shows its title, a long one scrolling with whole characters; Recently
played heads its days 今日, 昨日, with SFC and PS; Wi-Fi, Bluetooth,
Power and About read correctly. A ROM copied from a Mac with an accent in
its name reads correctly in either language. Auto:

```
grep '^system.language' /storage/.config/system/configs/system.cfg   # ja_JP after the switch
ls -l /usr/share/portarelauncher/                    # ja26.bin, ja26.NOTICE, OFL-1.1.txt
journalctl -u portarelauncher -b | grep ja26         # nothing: the glyphs loaded
```

## Power and hardware

### P1 Charge current throttle (auto)

```
systemctl is-active charge-throttle
journalctl -u charge-throttle --no-pager | tail
cat /sys/class/power_supply/battery/{temp,constant_charge_current}
```
Below 40 °C the limit equals `constant_charge_current_max`. Play a 3D game
on the charger until `temp` passes 400: the journal logs
`charge current 3000000 uA` and the file reads 3000000; at 420 it reads
2000000; cooling to below 380 restores the maximum. The script checks the
limit against the current temperature using the table in the service.

### P2 Suspend and resume (human+auto)

Press power: screen off within two seconds. Auto during suspend, from a
second device on the charger-less Nova: not possible over SSH (Wi-Fi is
down); instead read `current_now` before and after a one-hour suspend and
compute drain from `charge_now`. Under 1 % an hour passes. Wake: panel,
Wi-Fi (`ping`), gamepad (every button in the launcher), LEDs, microSD
(`ls /storage/roms`) all work; `dmesg` after resume has no `PCIe` or `ufs`
errors.

### P3 Fan control (auto)

```
systemctl is-active fancontrol
cat ${DEVICE_PWM_FAN}_enable    # 1
cat ${DEVICE_PWM_FAN}           # 0 when the CPU thermal zone is below the first curve step
```
Run a 3D game for ten minutes: `pwm1` rises with `thermal_zone` cpu
temperature and never sits at 255 below 70 °C.

### P4 microSD at SDR104 (auto)

```
cat /sys/kernel/debug/mmc*/ios | grep -E 'timing spec|clock'
```
`timing spec: 6 (sd uhs SDR104)` and `clock: 202000000 Hz` with a UHS-I
card inserted.

### P5 1000 Hz tick, teo, schedutil (auto)

```
zcat /proc/config.gz | grep -E '^CONFIG_HZ_1000=y|^CONFIG_ENERGY_MODEL=y'
cat /sys/devices/system/cpu/cpuidle/current_governor    # teo
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor  # schedutil
```

### P6 Optional debug tools (auto)

`OS_BUILD` in `/etc/os-release` says whether the build is official.
Nightlies and releases are both official and omit the debug set by default;
an unofficial local build includes it. `DEBUG_PACKAGES=yes` explicitly
enables it for either. Check the eight tools listed in
[the debug guide](DEBUG_TOOLS.md#where-the-tools-run), and run `strace -V`
against the version selected by the build rather than a fixed old version.

### P7 Gamepad MCU and stick LED rails off in suspend (auto+human)

Auto, idle: the rail exists and is held only by its consumers, none of
them always-on.

```
for r in /sys/class/regulator/regulator.*; do
  [ "$(cat $r/name)" = vdd_mcu_3v3 ] && cat $r/state $r/num_users
done                                                # enabled, 3
dmesg | grep -i 'MCU supply'                        # nothing
```
After a suspend and resume: `dmesg` has no "Failed to enable MCU supply"
or "Failed to enable regulator on resume" line, the sticks and every
button work in the launcher, and the stick LEDs show their colour again.
Human: with P2, an overnight suspend on battery; the drain before and
after nightly 156 is the number that says whether this helped #62.

## Media

### M1 mpv direct to the display (auto+human)

Play a 1080p H.264 file from the launcher's Movies system. While it plays:

```
pgrep -af mpv | grep -o -- '--gpu-context=displayvk'
cat /sys/kernel/debug/dri/0/clients            # mpv holds DRM master
top -bn1 | grep mpv                            # well under one core
```
The iris decoder in use shows as low CPU (decode.conf records 4 to 5 % of
a core for hardware against 16 to 66 % for software). Human: playback is
smooth, quit and reopen resumes at the same position (a file appears
under `/storage/.config/mpv/watch_later`). Repeat with a HEVC file; a VP9
file plays in software without error.

### M2 SD at 4:3 with scanlines (human)

Play a 712×478 DVD rip with no aspect flag: the picture fills the 4:3 panel
and has visible scanlines. Play a 1080p file: no scanlines, with its source
aspect ratio preserved.

## Build and process

### B1 Incremental nightly (auto, GitHub)

Two consecutive nightlies with a one-package change: the second finishes
in under a third of the full-rebuild time and its log restores the saved
state. A nightly after `rebuild: full` takes the full time.

### B2 Thread logs in the job output (auto, GitHub)

Break a package on a branch (a bad `PKG_SHA256`), push, and the failing
job's "Print the failing thread logs" step shows that package's thread log
with the error. Read the tail of `output.log` first: a thread named in the
summary may have been terminated because another job failed. Revert.

### B3 Package dependency check (auto, CI)

Add a dependency on a package that does not exist on a branch; CI fails
on `check-package-deps.py` naming it. Revert.

### B4 Commit linter (auto, CI)

Push a commit titled without the `package: ` prefix or over 72 characters;
`validate-commit` fails on it. Revert.

## Sign-off sheet

Copy this table into the PR that updates FEATURES.md after a test round.

| Build | Tester | Auto passed / total | Human passed / total | Failures |
|---|---|---|---|---|
| image version and commit | | | | |
