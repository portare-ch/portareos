# Known bugs and loose ends

Reviewed 24 October 2026 against the current tree and recorded Nova tests.
An implemented fix is not a device test. Items below distinguish observed
failures from checks still needed; each has a next action.

GitHub issues track work; the [roadmap](ROADMAP.md) sets priorities.
Older reproductions, rejected explanations and resolved bugs are preserved
in the [investigation history](documentation/BUG_HISTORY.md). Commands there
may refer to removed programs or older kernels.

## Emulators

### nova-push and the Neo Geo CD folder name

Resolved in the current PortareOS tools: `nova-push neocd` converts CUE
inputs and transfers the CHDs to `/storage/roms/neocd/`. Update older copies
that recognize only `neogeocd`; that name is not the device's folder.
The [installation guide](documentation/INSTALLATION.md) uses `neocd`.

### Dolphin hangs and audio problems

GameCube remains broken in the libretro path
([#463](https://github.com/portare-ch/portareos/issues/463)). Soul Calibur II
has hung after a FIFO error. An audio-driver fix restored batches that
exceeded RetroArch's small PipeWire ring, but clean gameplay with sound has
not been established. Older standalone `Dolphin.ini` experiments do not
establish the current core's behavior.

Reproduce with the shipped core; keep RetroArch's log, `/var/log/exec.log`
and `dmesg`. While frozen, identify the RetroArch PID and collect all-thread
backtraces with gdb. Separate an emulator deadlock from a graphics-driver
wait before changing settings. See the
[debug tools guide](documentation/DEBUG_TOOLS.md) for collection commands.

### Flycast: Tony Hawk regression check

Tony Hawk's Pro Skater dropped from its intended 30 fps to 26 or less with
audio stutter in standalone Flycast. Changing audio backends and pinning
the GPU did not fix it. That frontend, its `emu.cfg` and `start_flycast.sh`
are gone; RetroArch now owns audio and presentation.

Replay the same section with the current libretro core and record
application/display intervals and xruns. If it is clean, close the old
finding as removed with the standalone. Do not apply the old backend or
compositor experiments to the current image. See the
[performance plan](documentation/PERFORMANCE_PLAN.md).

### PlayStation and PS2: remaining coverage

SwanStation's preemptive-frame readback cost was reduced by patch 002
([#495](https://github.com/portare-ch/portareos/pull/495)). PlayStation's
PRMPT switch is available again, off by default, with higher CPU/GPU clocks
while enabled. The old claim that the switch was removed is obsolete.
Measured throughput, remaining missed refreshes and settings are in
[SwanStation](documentation/emulators/SwanStation.md).

ARMSX2 is playable through libretro; tuning and compatibility work continues
([#477](https://github.com/portare-ch/portareos/issues/477)). Recheck Time
Crisis II's glitches and speed against the standalone baseline. PS2 has no
RetroAchievements because the core exposes no memory to RetroArch. See
[ARMSX2](documentation/emulators/ARMSX2.md) for measured configurations.

### Guides and preemptive frames

M2 guide handover worked on a 2D core; returning from a guide still needs
explicit tests on Vulkan cores such as ParaLLEl N64 and Flycast. Check
graphics-context recovery, audio and the first seconds of resumed play.

Neo Geo CD now enables one preemptive frame by default, with Metal Slug and
Metal Slug 2 pause/resume checks recorded. Other consoles keep it off.
SNES and PlayStation have performance measurements, but every offered core
still needs deterministic save/load and input tests. Watch for
`[Run-Ahead Preemptive]` failures and flicker after a changed input; a
metadata claim of deterministic states alone is insufficient. See
[NeoCD](documentation/emulators/NeoCD.md) and the
[test plan](documentation/TEST_PLAN.md#e2-preemptive-frame-per-2d-console-autohuman).

## Display

### The color profiles crush the dark greys

Gamma 2.2 and sRGB collapsed dark steps that remained visible with stock
on 26 September. Stock remains the default, and the one-shot
`colorprofile-stock` migration resets earlier selections. Refit the low
codes and verify grey ramps on the panel before recommending either profile.
De-gamma and 8bpc dithering also need device checks. See
[color profiles](documentation/PER_DEVICE_DOCUMENTATION/SM8550/COLOR_PROFILE.md).

### External displays: wider validation remains

A monitor replaces the panel while it is connected (`external-display`
forces the panel's connector off; #710). Adaptive-Sync detection and DPU AVR
on DisplayPort are now implemented (#714), with the effective minimum
raised to at least 65 Hz (#716). The LG UltraGear+ showed NeoCD at
59.62 fps and 119.24 Hz on the #714 test kernel. Recheck the later floor
change, other monitors and adapters, and every rendering path; a running
game still keeps the output it started on until it exits.

USB host-mode teardown and DP unplug runtime-PM fixes (#708, #711) address
the oops and interrupt storm seen on disconnection. Test repeated hotplug,
display ownership, return to the panel and idle power on the current image.
DP output is capped at 8 bpc (#713). DisplayPort audio was deliberately
removed (#709); sound stays on the local outputs.

### VRR and Steam validation

The built-in panel's current range is 65–120.198 Hz. The launcher and Steam's
gamescope use VRR too, and Steam is capped at 60 fps. Probe measurements
support the new floor and repeat scheduling; a real Steam game on the final
kernel/gamescope combination is still unmeasured. Check frame delivery,
late-frame recovery and display transitions. RetroArch rejects rates that
cannot fit twice into the selected display mode, including some arcade
boards near 61 Hz on the built-in panel. See
[variable refresh](documentation/VARIABLE_REFRESH.md).

## Audio

RetroArch defaults to 8 ms. The current PipeWire path permits a 3 ms graph
quantum at 32, 44.1 and 48 kHz; pull-mode position reporting and removal of
batch headroom have been measured. The earlier 24 ms default and
"#428 merged, not run" notes describe intermediate builds.

The remaining work is end-to-end button-to-sound and audio/video alignment,
longer cross-core playback tests, headphones, Bluetooth and output changes.
Measure the threaded audio pipeline rather than adding its nominal target
to the budget by assumption. A smaller DSP period and direct ALSA did not
improve the measured queue. See [audio latency](documentation/AUDIO_LATENCY.md)
for current settings and the investigation log.

Automatic output-rate selection still needs explicit N64 coverage after
the game programs its DAC: compare `[Audio] Output rate picked` and the
PCM's `hw_params`, then listen through rate changes. The tested speaker
rates do not establish headphone or Bluetooth behavior.

## Power and resume

### Platform sleep works; overnight validation remains

The earlier "SoC never sleeps" finding is superseded by #658. Nightly
20261018 (`9d0a1c9`) entered CX, AOSS and DDR sleep and resumed in both a
30-second and a 10-minute test. The latter measured **23 mA**, against
39 mA over 5.9 hours on the preceding nightly. These are different test
durations, not a current overnight comparison.

Linux 7.3 exposed another blocker: the disabled QCE driver left the crypto
engine's interconnect suppliers holding boot votes. The device tree now
disables the unused crypto node (#728). Recheck the sleep counters on the
current kernel; the 18 October measurements predate this change.

Run an overnight battery test, repeated short cycles, suspend with an open
playback PCM, charger attachment while asleep, and speaker/headphone checks
after wake. Wi-Fi returned within a second in the recorded test; the old
10.6-second NetworkManager-era delay is no longer the current baseline.
Investigate the new `hwmon ... parent phy0 should not be sleeping` resume
warning if it produces a failure. Full evidence and earlier failed
hypotheses are in [power measurements](documentation/POWER.md).

### Charging-current limits remain unverified

Kernel patch 0510 and `charge-throttle` implement a firmware current ceiling
and temperature steps at 40, 42 and 44 °C. Verify
`constant_charge_current_max`, a supported current-limit write, and
`current_now` while charging; watch `journalctl -u charge-throttle -f` as
the battery warms. A rejected property or
`no charge current limit on this kernel` means the mitigation is ineffective.

### RT threads keep clocks high

NeoCD's emulation uses about a tenth of a middle core, yet the X3 remains
at 2957 MHz for mostly idle real-time audio/GPU threads. The default RT
utilization clamp is 1024. Lowering it globally or moving threads with
coarse masks increased late frames or CPU cost in recorded tests; all three
experiments were rejected. Measure a per-thread or kernel policy across
systems; see [NeoCD's measurements](documentation/emulators/NeoCD.md).

### Gamepad report loss and suspend indicators

200 Hz MCU reporting survives resume. At 250 Hz, about 19% of reports did
not reach evdev; values 0 and 1 stopped the pad. Trace the loss before
raising the default. `rsinput_process_data()` also drops a partial frame at
the end of a callback instead of reassembling it across callbacks.

The suspend hooks and power handler write `/sys/class/leds/power-led`,
which the Nova does not expose. The guarded writes do nothing; the stick
LEDs are separate. Test a real indication before claiming feedback during
the suspend transition. Bluetooth controller reconnect after resume and
MCU/LED rail power-off still need explicit device checks.

## Build and configuration

`tools/device-tests` predates several current defaults: it still expects a
256-frame audio quantum, unconditional fixed-mode panel selection and old
automatic-frame-delay/PlayStation profile behavior. Update those assertions
and demonstrate failure on deliberately wrong settings before relying on
the checker as a current regression gate. The
[test plan](documentation/TEST_PLAN.md) records the current expectations.

Changed defaults in persistent files need one-shot migrations; copying new
files with `--ignore-existing` does not update values in existing files.
Fresh installs now mark the existing migrations as done (#638).
`retroarch.cfg` and `retroarch/config/`, including seeded core options, are
deliberately refreshed on update; the first copy is kept at
`config.pre-refresh`. Changes in those managed paths may overwrite menu
edits. Test both fresh and updated devices when changing defaults.

The kernel patch-fuzz count from 26 September was for Linux 7.2.5 and
97 patches. It is historical, not the current Linux 7.3 stack. #658 recorded
121 production patches applying and nine changed objects plus the DTB
compiling; that does not establish zero fuzz. If tightening patch policy,
measure the current stack without `patch -s`, retain its output and test a
deliberately rejected hunk. The old patch list is in the investigation
history.
