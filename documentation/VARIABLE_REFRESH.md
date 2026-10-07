# Variable refresh on the Nova

The goal is integer-multiple variable refresh. Every game frame is
scanned exactly twice, and the panel follows the game at twice its rate:
PAL at 100 Hz, NTSC at 119.88 Hz, SwanStation's 59.826 at 119.652 Hz.
That needs no panel mode per console, and nothing outside 100 to 121 Hz.
The panel takes a frame length that changes every frame inside that range
(measured below), and patch 1097 exposes it through DRM's standard
variable-refresh properties.

## What the hardware offers

- **Android** drives the panel, an il97680a 4.5" 1280x960 AMOLED, in
  command mode with the TE pin. It has two timings, 120 and 60 Hz,
  switched by DCS register 0x60, and no Qsync properties or commands. The
  same device tree enables Qsync for Qualcomm's reference panels.
- **PortareOS** drives it in video mode (kernel patch 0105). The
  per-console modes change the pixel clock.
- **The DPU's INTF has AVR**, the block Qualcomm's downstream driver uses
  for Qsync in video mode: the vertical front porch runs on until a
  trigger, up to a set frame length. Mainline defines its registers and
  programs none. Downstream writes the longest frame to `AVR_VTOTAL`, sets
  bit 0 of `AVR_CONTROL` and bits 0 and 8 of `AVR_MODE` for one-shot, and
  writes `AVR_TRIGGER` after every commit. The SM8550 driver also sets
  `AVR_SUPPORT_ENABLE`, bit 29 of the DSI host's video mode control
  (`DSI_VIDEO_MODE_CTRL`, mainline's `REG_DSI_VID_CFG0` plus the 6G
  shift, 0xae94010 on the Nova), when it switches Qsync on.
- **Kernel patch 1097** adds it as DRM's standard interface:
  - The panel driver declares its range, 90 Hz up to its fastest mode,
    120.198 Hz rounded up to 121, in the connector's
    `display_info.monitor_range` and sets `vrr_capable`, which DSI
    connectors now carry.
  - At mode set the DPU writes the longest frame, from the range's
    minimum.
  - The CRTC's `VRR_ENABLED` switches AVR on and off in a commit, without
    a mode set, with the INTF in that commit's flush and the DSI host's bit
    29 alongside, in continuous mode.
  - The kernel logs `intf1: variable refresh on` and `off`. From DPU 8.1,
    bit 31 of `AVR_CONTROL` reads 1 while AVR is active.

## Measured, 2026-10-07

### A stretched front porch, static

`vrr-probe` static phases: the preferred mode's 156.24 MHz pixel clock and
a longer vertical front porch, set through ordinary mode setting.

| Rate | Front porch, lines | Frames in 10 s |
|---|---|---|
| 119.88 Hz | 12 | 1200 |
| 110 Hz | 102 | 1100 |
| 100 Hz | 211 | 1001 |
| 90 Hz | 344 | 901 |
| 80 Hz | 511 | 801 |
| 72 Hz | 678 | 721 |
| 60 Hz | 1011 | 600 |

Every rate ran exactly, with no DSI or DPU error. By eye, at normal
brightness, the picture was stable with no flicker at every rate. Low
brightness is not checked yet.

The panel's TE pin, GPIO 86, cannot be read as a GPIO: the pin controller
refuses it while the DSI holds it as `mdp_vsync`.

### Frames on a schedule, fixed refresh

`vrr-probe` dynamic phases on the 120.198 Hz mode, without AVR. The
start is the kernel's flip timestamp against the scheduled commit.

| Schedule | On the 8.32 ms grid | Start after schedule, median | Frame lengths |
|---|---|---|---|
| 120 Hz | 100% | 5.7 ms | 8.3 ms |
| 119.652 Hz | 100% | 6.3 ms | 8.3 ms |
| 110 Hz | 100% | 5.8 ms | 8.3 ms, 16.6 ms in 1 of 11 |
| 100 Hz | 100% | 5.8 ms | 8.3 ms, 16.6 ms in 1 of 5 |
| 100 and 120 alternating | 100% | 5.8 ms | 8.3 ms, 16.6 ms in 1 of 10 |
| Random, 8.34 to 10 ms | 100% | 5.6 ms | 8.3 ms, 16.6 ms in 1 of 10 |
| Game frames of 16.7 to 20 ms, each twice | 100% | 5.7 ms | 8.3 ms, 16.6 ms in 1 of 10 |

With AVR the same schedules should start frames off the grid, within
about a millisecond of each commit, and the frame lengths should follow
the schedule.

### AVR switched on at mode set: inactive

The first version of patch 1097 enabled AVR at mode set, before the
timing engine started. The registers read back as programmed:
`AVR_CONTROL` 0x1, `AVR_MODE` 0x101, `AVR_VTOTAL` 1250 lines. The status
bit stayed clear, frames ran at 119.98 Hz with no commits instead of the
96 Hz floor, and every dynamic schedule landed on the 8.32 ms grid as on
the fixed refresh. No flicker was seen, but on fixed timing.

Switched on in the first commit after the mode set, with the INTF in
that flush, it stayed inactive the same way: status bit clear, 119.5
frames/s with no commits. The DSI host's `AVR_SUPPORT_ENABLE` was still
clear (`0x10009130`); the patch now sets it.

With the DSI bit set (`0x30009130`), AVR stayed inactive again: status
bit clear, 120.5 frames/s with no commits. One difference left in plain
sight: downstream always enables programmable fetch in video mode, at
least one line ("prog fetch always enabled case"); mainline turns it off
when the back porch is long enough, as here (`PROG_FETCH_START` 0). The
patch now carries that and the other candidates as parameters, so one
build can try them all:

| Parameter | Default | What it changes |
|---|---|---|
| `dpu_avr_prog_fetch` | 1 | Programmable fetch lines while AVR is wanted, where the porches need none |
| `dpu_avr_continuous` | Y | Continuous AVR instead of one-shot |
| `dpu_avr_at_modeset` | N | Switch AVR on at mode set instead of in the first commit |
| `dpu_avr_flush_intf` | N | Flush the INTF on every commit |
| `dpu_avr_dsi` | Y | The DSI host's AVR support bit |

All were under `/sys/module/msm/parameters/`. Once continuous mode was
found they came out again, for the interface above; the measurements
below used them.

### AVR working: continuous mode

On the kernel with the parameters (kernel-only build, 2026-10-07), the
idle check per combination, floor 96:

| Combination | `AVR_CONTROL` | Idle frames/s |
|---|---|---|
| One-shot, any fetch, DSI bit, enable point or per-commit flush | 0x00000001 | 120 |
| Continuous, with fetch and DSI bit | 0x80000001 | 96 to 97 |
| Continuous, without programmable fetch | 0x80000001 | 96.1 |
| Continuous, without the DSI bit | 0x80000001 | 95.9 |

Continuous mode alone engages AVR; one-shot, downstream's Qsync default,
never did.

Frames on a schedule, continuous, floor 90, the probe's own receive
times against its commits:

| Schedule | Commit to frame, median | Frame length error, median | p95 |
|---|---|---|---|
| 120 Hz | 1.11 ms | 0.03 ms | 0.46 ms |
| 119.652 Hz | 0.85 ms | 0.05 ms | 0.40 ms |
| 110 Hz | 0.50 ms | 0.19 ms | 0.72 ms |
| 100 Hz | 0.78 ms | 0.27 ms | 1.56 ms |
| 100 and 120 alternating | 0.66 ms | 0.20 ms | 0.87 ms |
| Random, 8.34 to 10 ms | 0.36 ms | 0.25 ms | 0.86 ms |
| Game frames of 16.7 to 20 ms, each twice | 0.32 ms | 0.11 ms | 0.66 ms |

On the fixed refresh the same 100 Hz schedule had 4.9 ms from commit to
frame and a p95 error of 7.1 ms. A floor of 96 was too tight for 100 Hz:
its longest frame, 10.4 ms, left 0.4 ms for a commit to get through the
kernel, and missed frames fell back onto the 8.3 ms grid (p95 error
9.6 ms). Floor 90 gives 1.1 ms.

By eye, 2026-10-08, with AVR on (floor 90, continuous) and the backlight
at 172 of 3445: no flicker or brightness change in any schedule, the
alternating 100 and 120 Hz one included. That run's log confirms AVR was
on: 100 Hz frames came 9.9 to 10.1 ms apart, p95 error 0.71 ms.

The kernel's flip timestamps are not usable under AVR: DRM derives them
from the scanout position against the mode's fixed frame length, and two
flips often came back with the same one. Mesa's and RetroArch's frame
timing read those timestamps, so a variable-refresh path has to fix them
or work without them.

## Running the AVR test

On a build with patch 1097. `vrr-probe` is in the debug set, which only
unofficial builds carry; elsewhere, copy the static build to `/storage`.
Its fourth argument, `vrr`, sets the CRTC's `VRR_ENABLED` for the run and
clears it on the way out; it prints the connector's `vrr_capable` first.

First, whether AVR holds the front porch at all. `idle` commits once
and then nothing, so frames should slow to the floor:

```
systemctl stop portarelauncher
vrr-probe /dev/null 6 idle vrr &
sleep 2
devmem 0xae36270 32          # 0x80000001: AVR active
F=0xae360ac; a=$(devmem $F 32); sleep 2; b=$(devmem $F 32)
echo $(( (b - a) / 2 )) frames/s   # about 90, not 120
wait
```

Then the schedules:

```
vrr-probe /storage/vrr-avr.csv 10 dynamic vrr
vrr-probe /dev/null 1 reset
systemctl start portarelauncher
```

The kernel logs `intf1: variable refresh on` when the CRTC property takes
effect. The big digit is the phase, 7 to 14, and the grey number
the rate (0 for a pattern). Watch the dark grey patches for flicker,
especially in phase 11, where the frame length alternates every frame,
and compare brightness with phase 7. Then repeat at minimum brightness.

### Through the interface, 2026-10-08

Kernel-only build of patch 1097 with the DRM interface, no parameters:
`vrr_capable` reads 1 on the DSI connector. With `VRR_ENABLED` set and
nothing committed, `AVR_CONTROL` read 0x80000001, the DSI bit was set and
frames ran at 90.01/s, the floor. Clearing `VRR_ENABLED`, without a mode
set, turned both off again: 119.92 frames/s. The schedules matched the
runs with the parameters; at 100 Hz the median frame-length error was
0.16 ms (p95 0.56 ms).

A schedule that starts behind the frame boundary catches up only by the
margin between its frame and the mode's shortest: at 120 Hz on the
120.198 Hz mode that is 14 us a frame, and one run started a whole frame
behind (8.3 ms from commit to frame) and was still 4 ms behind after
four seconds. At 119.652 Hz the margin is 38 us; lower rates recover
faster.

## Integer multiples for every game

AVR's shortest frame is the frame of the mode in use, so a doubled rate
fits only up to that mode's rate. With variable refresh on, the mode has
to be the fastest one, 120.198 Hz, twice the SNES. On the 119.652 Hz
mode, the PlayStation's, doubled SNES would not fit.

The multiple for a game is the largest k with k times its rate at most
120.198 Hz and at least the 90 Hz floor: 2 for 45 to 60.1 Hz, 3 for 30 to
40 Hz, 4 for 22.5 to 30 Hz. Userspace has to know the range from a device
quirk: DRM keeps `monitor_range` inside the kernel for a panel without
EDID.

Rates between 60.1 and 61 Hz, a few arcade boards, have no multiple in
range, and the range cannot grow upward. `vrr-probe fast`, 2026-10-08:
the fastest mode's 174.651 MHz clock and 12-line front porch, with the
back porch cut from 142 lines to 135 (120.956 Hz) and 126 (121.946 Hz).
The SoC delivered every frame exactly one period apart, within 10 us, at
all three rates. By eye the moving block jumped at 121 and 122 Hz and was
clean at 120.198: the panel does not show frames faster than its 120 Hz
class evenly. Those boards keep a fixed mode.

## Do not

Do not write the DPU's timing registers from userspace. Writing
`INTF_VSYNC_PERIOD_F0` on INTF 1 (0xae3600c) with `devmem` while the panel
ran rebooted the Nova, with no record of why. Use mode setting, or the
kernel patch.
