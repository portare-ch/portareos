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
  - The panel driver declares its range, 80 Hz up to its fastest mode,
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
echo $(( (b - a) / 2 )) frames/s   # about 80, not 120
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
120.198 Hz and at least the 80 Hz floor: 2 for 40 to 60.1 Hz, 3 for 26.7
to 40.07 Hz, 4 for 20 to 30.05 Hz. The floor is just under two thirds of
the fastest refresh, so every rate between has one; at 90 Hz, 40.07 to
45 Hz had none. DRM keeps `monitor_range` inside the kernel
for a panel without EDID; the repeat below needs only the mode's refresh.

Rates between 60.1 and 61 Hz, a few arcade boards, have no multiple in
range, and the range cannot grow upward. `vrr-probe fast`, 2026-10-08:
the fastest mode's 174.651 MHz clock and 12-line front porch, with the
back porch cut from 142 lines to 135 (120.956 Hz) and 126 (121.946 Hz).
The SoC delivered every frame exactly one period apart, within 10 us, at
all three rates. By eye the moving block jumped at 121 and 122 Hz and was
clean at 120.198: the panel does not show frames faster than its 120 Hz
class evenly. Those boards are locked to the display instead, at half its
rate (see the launch below). That test ran on the wide back porch the panel
does not lock to (see the porches below); on its own porches it has not been
repeated, so the range above 120.198 Hz is open again.

## Showing a frame more than once

The repeat is the display driver's (patch 1107, see
[repeats in the kernel](#repeats-in-the-kernel-lfc)). Until 2026-10-09 it
lived in Mesa's KMS backend (`mesa-005`, dropped then), as described here
with what was measured on it. RetroArch presents
each frame once (`0018`), aimed at the frame's start plus a budget: what
the last 64 frames needed to be ready, measured after the GPU fence, and
a millisecond. Mesa takes the frame period from the distance between
targets. If that is at least twice the mode's refresh, Mesa commits the
same buffer again at target + period / N once the frame has flipped. The
application keeps both swapchain images and the whole frame period, and a
repeat costs one atomic commit and no rendering. Mesa derives N from the
mode's refresh alone, so it needs no range quirk.

Rejected first: RetroArch re-rendering each frame twice. The second
present held the image the next frame needed until it was on screen, so
with two images the core had about half a frame instead of a whole one,
and the shader ran twice. Tekken 3 at 4x with a 12-pass shader: 20% of
frames started late and 62 refreshes in 30 s fell to the 11.1 ms floor.
Three images hid that, but the design was the fault, not the image
count.

Measured 2026-10-08, VRR on, two swapchain images, flip traces:

| | Frames | Refreshes | Self-refreshes | Longest refresh |
|---|---|---|---|---|
| Super Mario World, 30 s | 1804 | 3607 | 0 | 8.51 ms |
| Tekken 3 attract, 60 s | 3588 | 7181 | 5, all on frames the game delivered late while loading | 11.13 ms |

The SNES is the edge case: half its frame is the fastest refresh, so the
panel cannot catch up once it is behind. It sat a steady 7.5 ms behind
the targets: fixed latency, as on a fixed 120 Hz mode, with every frame
still shown twice. A PlayStation frame leaves 0.038 ms a refresh to catch
up, about a second after a loading stall.

The general form is LFC in the DPU driver, which covers every client,
not only timed VK_KHR_display presents: patch 1107, which replaced this.

## Checked frame by frame

Measured 2026-10-08 for #595, with the image of that day and RetroArch
0020. A refresh count or an average frame rate cannot show that every
frame was shown k times, so each run was traced and checked one refresh at
a time: `tools/display-trace` records every vblank, every flip, the buffer
each commit scans out, Mesa's commits (`mesa-007`: frame or repeat,
present ID, target, when it was queued and committed) and, for
present-probe, the DPU's CRC of every refresh. `tools/display-check` pairs
each commit with the vblank its flip completed on. Each refresh is then a
new frame, a repeat, or one with no commit: the panel refreshing on its
own at its 90 Hz floor. Games ran 10 minutes with MangoHud observing
(#596), present-probe 5 minutes per rate with every 600th frame presented
3 ms late, the boundaries 60 s each.

| | k, P/k | Frames | Shown k times | Without a commit | Late or tight presents | Not explained |
|---|---|---|---|---|---|---|
| Super Mario World, 60.099 Hz | 2, 8.320 ms | 35989 | 35986 | 4 | 428 / 3254 | 0 |
| the same without MangoHud | | 35989 | 35987 | 3 | 268 / 3750 | 0 |
| Tekken 3, 59.826 Hz | 2, 8.358 ms | 35818 | 35791 | 30 | 898 / 2476 | 1 phase jump |
| Streets of Rage 2, 59.923 Hz | 2, 8.344 ms | 35884 | 35868 | 16 | 152 / 3480 | 1 frame |
| present-probe, 60.099 Hz | 2, 8.320 ms | 17998 | 17992 | 3 | 77 / 22 | 0 |
| present-probe, 59.94 Hz | 2, 8.342 ms | 17953 | 17907 | 44 | 74 / 3 | 3 phase jumps |
| present-probe, 59.826 Hz | 2, 8.358 ms | 17917 | 17877 | 38 | 50 / 3 | 3 frames, 4 jumps |
| present-probe, 50 Hz | 2, 10.000 ms | 14976 | 14912 | 62 | 36 / 5 | 24 frames, 24 jumps |
| present-probe, 40 Hz | 3, 8.333 ms | 11981 | 11957 | 23 | 33 / 1 | 0 |
| present-probe, 30 Hz | 4, 8.333 ms | 8984 | 8961 | 22 | 25 / 2 | 0 |

Late is a present that reached Mesa after its target; tight, one that
reached it after Mesa's own commit point, a millisecond before. Every frame
not shown k times sits at one of those, with the exceptions in the last
column. The mean display interval matched the content's period to 0.003%
or better in every run, and against the content's own clock the panel
stayed within a frame, minute by minute (the SNES's 8.9 ms range being
the widest).

- **Repeats show their frame.** Each repeat scanned out the buffer of the
  frame before it, in all 21 runs. In present-probe, which draws its frame
  number, the DPU's CRC agreed on all 283,415 refreshes: a repeat or a
  refresh without a commit has its frame's pixels, a new frame new ones.
- **MangoHud's display intervals are the trace's**: 189,433 rows in nine
  runs, each equal to the vblank timestamps to the microsecond. Without
  MangoHud the panel did the same, 35,987 frames shown twice against
  35,986. With it, 428 presents came late against 268, the overlay's own
  cost, and in two present-probe runs it held one present back about
  20 ms some 3 s after start.
- **The SNES cannot catch up.** Half its frame is the panel's shortest
  refresh, so after a late frame the panel stays behind. The phase against
  the targets moved between 5.5 and 10.6 ms, as RetroArch moved them: 91
  of 94 jumps were 0018's budget stepping. Against the content's clock it
  stayed within a frame. The other rates catch up k x (P/k - R) per
  frame: after a 3 ms late frame, which slips a whole refresh, a median
  138 frames at 59.826 Hz, 237 at 59.94, 255 at 40 and 191 at 30 Hz.
- **The rest is on the display side**, a few times per run: the plane
  programmed late after Mesa's commit (over 2 ms on 6 to 11 of about
  72,000 commits per game, against a median of 0.09 ms; 2.9 to 3.1 ms
  where it cost a refresh), or a repeat committed up to 2.2 ms after it
  was due. A frame is held a refresh when that meets the panel's floor.
  The cause is not found; the commit worker and the wait in patch 1098
  are where to look.
- **50 Hz runs close to the floor.** A repeat's 10 ms refresh is 1.1 ms
  short of the 11.1 ms floor, and a repeat committed 0.9 ms late, with the
  plane programmed 1.0 ms before the floor, did not start a refresh: the
  panel refreshed on its own and the frame waited. 62 times in 5 minutes,
  so a PAL game would hitch about every 5 s. The floor is 80 Hz since,
  below.

The edges of k, present-probe at 60 s each:

| Rate | k, P/k | What the panel did |
|---|---|---|
| 60.05, 40.066, 30.049, 29.9 Hz | fits | every frame exactly k times |
| 60.15, 40.2, 30.1 Hz | mesa-005's R/50 slack picks a k below the shortest refresh | 6, 24, 12 frames a minute shown one refresh short; the content 0.01-0.02% slow |
| 60.5 Hz | 2, 8.264 ms | the panel at its fastest, the content 0.6% slow; RetroArch locks it to the display instead (0019) |
| 45.1 Hz | 2, 11.086 ms, just inside the floor | 39% of frames with a refresh of the panel's own |
| 44.9 Hz | 2, 11.136 ms, past the floor | 46% |
| 42 Hz | 2, 11.905 ms: no k fits | 60% |

The slack exists so a frame of exactly two refreshes, the SNES on its own
mode, keeps both, and that takes more than microseconds: RetroArch lowers
its budget 0.5 ms at a time (0018), mesa-005's period takes an eighth of
the step, and in the 10 minutes above Super Mario World's period fell
62.5 us short of two refreshes 44 times. At R/50, 166 us, it also takes k
at 40.07 to 40.33 and 30.05 to 30.20 Hz, which RetroArch's check for
content that does not fit twice does not catch. On the 90 Hz floor one
refresh fewer would have been worse at all three: 60.15 Hz shown once is
past the floor, 40.2 Hz twice is 12.44 ms, past it too, and 30.1 Hz three
times is 11.07 ms, 0.03 ms inside it (45.1 Hz above was 0.02). Between
40.07 and 45 Hz nothing fits the 90 Hz floor at all, and the floor's own
margin pushes the usable lower edge for k = 2 up towards 50 Hz.

### On an 80 Hz floor

Patch 1097 declares 80 Hz since, just under two thirds of 120.198 Hz: the
longest frame AVR holds is 12.5 ms (1676 lines on the 1116-line mode of the
time), and the idle check above
reads 80 frames/s. Every rate from 20 to 60.1 Hz has a multiple now, and a
repeat at 50 Hz has 2.5 ms to the floor instead of 1.1. Measured
2026-10-08 on a kernel-only build over that day's image, with the same
Mesa, RetroArch and runs. Frames over 11.1 ms have not been watched at
low backlight yet. Refreshes the panel made on its own:

| | P/k | To the 80 Hz floor | At 90 Hz | At 80 Hz |
|---|---|---|---|---|
| present-probe 50 Hz, 5 min, every 600th frame late | 10.000 ms | 2.49 ms | 62 | 31, all at late presents |
| 49.76 Hz, 60 s | 10.048 ms | 2.45 ms | | 4 |
| 45.1 Hz | 11.086 ms | 1.41 ms | 1039 | 3 |
| 44 Hz | 11.364 ms | 1.13 ms | | 8 |
| 43 Hz | 11.628 ms | 0.87 ms | | 19 |
| 42 Hz | 11.905 ms | 0.59 ms | 1496 | 125 |
| 41 Hz | 12.195 ms | 0.30 ms | | 197 |
| 40.4 Hz | 12.376 ms | 0.12 ms | | 693 |
| Tekken 3, the first 290 s | 8.358 ms | 4.14 ms | 20 | 6 |
| present-probe 59.826 Hz, 5 min, every 600th frame late | 8.358 ms | 4.14 ms | 38 | 34 |

40.066, 40, 30.049 and 29.9 Hz showed every frame k times, and 40.2 and
30.1 Hz one refresh short 24 and 13 times a minute, as before.

- **A repeat needs about 1.4 ms to the floor.** Below that the panel
  refreshes on its own more often the closer the repeat comes, as 45.1 Hz
  did on the 90 Hz floor with 0.02 ms. 50 Hz no longer misses one: the
  rest of its 31 are at the deliberately late frames, and its 2 phase
  jumps not explained are the plane programmed 2.3 and 2.5 ms after the
  commit, the display-side delay above.
- **On a 60 Hz game it only matters to a late frame.** A frame on time is
  refreshed every 8.4 ms, far from either floor. A late one is committed
  at once, and a commit still starts the refresh if it lands 1.6 to 1.8 ms
  before the floor runs out: 10.9 ms after the refresh before at 80 Hz,
  9.3 ms at 90 Hz. For a 60 Hz game that is a present up to about 3 ms
  after its target, against 1.3 ms; later, the panel refreshes on its own
  and the frame before is shown a third time. In Tekken 3, frames shown
  three times in the same 290 s fell from 13 to 4, those 4 presented more
  than 4 ms late, while loading. present-probe's late frames reach Mesa
  3.9 ms after their target, past both floors, and on the lower one the
  panel's own refresh and the frame after it come 1.4 ms later.
- **The slack stays at R/50.** One refresh fewer at 40.2 Hz would be
  12.44 ms, 0.06 ms from the floor, worse than 40.4 Hz above; at 30.1 Hz,
  11.07 ms, 1.42 ms from it, about 45.1 Hz's 3 a minute. So less slack
  would help only 30.05 to 30.20 Hz, where nothing runs, and the SNES needs
  more than 62.5 us of it.

`tools/display-check` takes the floor as `--floor-hz` (80 by default; 90
for the runs before), and counts a phase jump back towards the usual
phase as the panel catching up, k x (P/k - R) a frame: 3.4 ms at 50 Hz,
over the 2 ms jump. Of the 149 jumps at 50 Hz on the 90 Hz floor, 125
were that.

## Repeats in the kernel (LFC)

Patch 1107 repeats a slow frame in the DPU's video encoder instead of
in Mesa (#586). It was compared with mesa-005 on the same image, below,
and replaced it: on by default, `msm.dpu_lfc=0` turns it off and leaves
a slow frame to the panel's own refresh at the floor.

- **Period.** The kickoffs of a steady source fall on a grid, the
  content's own clock, which stands in for mesa-005's targets. A kickoff
  within an eighth of a period of its place pulls the grid and its
  period a little towards itself; a late or dropped one moves neither, so
  a late frame's repeats keep their places and the panel catches up on
  them. Two distances alike are a new rate, and the grid starts again
  from them, as from the first two, when both kickoffs missed the grid
  or the distance is more than an eighth off the period: a doubled rate
  puts every second frame back on the old grid, so misses alone never
  noticed 30 to 60 Hz. A mode set and AVR going on or off start the
  cadence afresh. A frame is shown `count = (P + R/50) / R` times, none below two
  refreshes or above 100 ms. Smoothing the distances between kickoffs
  instead, as a first build did, failed at 40 Hz: the frame after one
  6 ms late came 18.8 ms after it, close enough to count, and three
  refreshes a frame became two for seven frames. `dpu_enc_lfc_frame`
  traces the grid at every kickoff.
- **Repeat.** After each refresh of a frame, the vsync interrupt arms an
  hrtimer for the next one at kickoff + shown x P/count, and the timer
  writes `AVR_TRIGGER`. A kickoff cancels what is left of the frame
  before, and a trigger finding one pending is skipped. A refresh the
  panel makes on its own, at the floor, counts like a repeat. No commit,
  no flip event, no atomic state.
- **Two races found on the device.** The vsync that takes a frame can
  come before the kickoff has put the frame on the grid; arming then
  timed the first repeat from the frame before, already past, and its
  trigger added a refresh (Tekken 3, 35 times in 10 minutes, each
  starting a run a refresh behind). The kickoff arms it in that case.
  And the encoder drops the vsync interrupt 58 ms after a frame when
  nothing holds it (`ENTER_IDLE`), so at 12 Hz the repeats stopped after
  6 to 8 of 9. `tools/display-trace` hides that, since `vblank-rate`
  holds the interrupt; `--no-hold` leaves it to the client. The encoder
  now holds it while AVR is on with LFC.
- **Clients.** Any commit while `VRR_ENABLED` is set, timed or not.
  For the comparison, Mesa's repeats could be turned off
  (`MESA_VK_WSI_DISPLAY_REPEAT=0`, mesa-008, dropped with mesa-005);
  with both on, the kernel took Mesa's repeats for frames and added none
  of its own. Change `dpu_lfc` between clients: the vsync interrupt is
  held from when AVR goes on.

Two things about AVR in continuous mode had to be found on the Nova,
with a build that had them as parameters (2026-10-09, present-probe,
30 s per run):

- **`AVR_TRIGGER` alone starts a refresh.** Flushing the INTF as well,
  the other candidate, was not needed.
- **A trigger written while the INTF still scans the refresh before is
  kept for that refresh's end**, as a commit's flush is. So the trigger
  goes at its place on the period, and where the panel is behind, the
  hardware starts the repeat at the shortest frame. Timing it from the
  vsync interrupt instead, never before the shortest frame after it,
  failed: the interrupt ran about 0.68 ms after the vsync (its trace
  time against the vblank timestamp), every repeat came that much late,
  9.0 ms apart at 30 Hz instead of 8.33, and 152 of 882 frames lost a
  repeat.

| Run | Frames shown k times | Refresh against P/k, median / p99 | Scanout - target, median |
|---|---|---|---|
| 30 Hz, k = 4, timed from the vsync interrupt | 728 of 882 | 0.211 / 1.011 ms | 4.12 ms |
| 30 Hz, k = 4, trigger on the period | 878 of 885 | 0.015 / 0.275 ms | 0.50 ms |
| 60.099 Hz, k = 2, trigger on the period | 1772 of 1775 | 0.002 / 0.007 ms | 1.27 ms |

`tools/display-check` pairs each `dpu_enc_lfc_repeat` kick with the
vblank traced after it and counts those refreshes as kernel repeats, so
the same checks apply to both. It also reports how long a kick took to
start its refresh and how far it went from its place on the period.

### Against mesa-005, a first look

2026-10-09, kernel-only build of patch 1107 over that day's image, one
Turnip build with mesa-008 for both sides (`VK_DRIVER_FILES`), only
`msm.dpu_lfc` toggled. present-probe, 60 s per run, every 600th frame
4 ms late, `tools/display-check --rate`.

| Rate | Repeats | Frames shown k times | Panel on its own | Refresh vs P/k, median / p95 / p99 ms | Scanout - target, median / p95 ms | Frames to recover from a late one | Checks failed |
|---|---|---|---|---|---|---|---|
| 60.099 Hz | Mesa | 3570 of 3574 | 2 | 0.002 / 0.006 / 0.007 | 14.09 / 14.18 | never | 0 |
| 60.099 Hz | kernel | 3574 of 3578 | 3 | 0.002 / 0.006 / 0.007 | 6.91 / 7.08 | never | 1 |
| 59.94 Hz | Mesa | 3561 of 3569 | 6 | 0.022 / 0.061 / 0.198 | 0.68 / 11.46 | 269 | 0 |
| 59.94 Hz | kernel | 3557 of 3570 | 7 | 0.022 / 0.075 / 0.250 | 0.48 / 3.36 | 82 | 0 |
| 59.826 Hz | Mesa | 3554 of 3562 | 6 | 0.038 / 0.089 / 0.289 | 0.37 / 10.38 | 156 | 1 |
| 59.826 Hz | kernel | 3544 of 3560 | 11 | 0.037 / 0.114 / 0.335 | 0.49 / 2.00 | 48 | 0 |
| 50 Hz | Mesa | 2969 of 2975 | 6 | 0.087 / 0.486 / 0.814 | 0.26 / 0.54 | 3 | 0 |
| 50 Hz | kernel | 2971 of 2977 | 8 | 0.072 / 0.330 / 0.664 | 0.28 / 0.88 | 3 | 0 |
| 40 Hz | Mesa | 2375 of 2381 | 5 | 0.014 / 0.021 / 0.218 | 0.85 / 11.63 | 287 | 0 |
| 40 Hz | kernel | 2372 of 2382 | 6 | 0.014 / 0.054 / 0.189 | 0.46 / 2.89 | 88 | 0 |
| 30 Hz | Mesa | 1781 of 1786 | 5 | 0.014 / 0.039 / 0.233 | 0.89 / 10.92 | 216 | 0 |
| 30 Hz | kernel | 1772 of 1786 | 6 | 0.014 / 0.052 / 0.228 | 0.54 / 2.17 | 66 | 0 |

- **On time, the two are the same.** Repeats land within microseconds of
  P/k either way, and a frame on time reaches the screen at the same
  phase: new frames go through the same commit path.
- **After a late frame they differ by design.** A 4 ms late frame misses
  the floor and is shown a refresh long on both. Mesa then commits the
  repeat of the next frame anyway, the frame after waits, and the panel
  runs a refresh behind until k x (P/k - R) a frame has made it up:
  156 to 287 frames, 2.5 to 7 s, which is the p95 phase of 10 to 12 ms.
  The kernel skips that repeat because the next frame is already kicked
  off, so one frame is shown a refresh short and the panel is back on
  the content's grid; what is left takes 48 to 88 frames. Two frames off
  their count instead of one, and a fraction of the time behind.
- **60.099 Hz never catches up** on either: half a frame is the fastest
  refresh, so only a skipped repeat moves it back. Both sat at a fixed
  offset after the first late frames, Mesa's twice the kernel's in this
  run. Which offset a run ends on depends on its history; a longer run
  is needed before reading the difference as a property of either.
- **Failed checks**: Mesa at 59.826 Hz, two jumps after a repeat
  committed 2.0 and 2.5 ms late, the userspace wakeup a kernel timer
  removes; the kernel at 60.099 Hz, one jump with no cause in the trace,
  of the kind seen before from the display side. Kernel triggers went a
  median 0.01 ms and a p99 0.11 ms after their place on the grid.

### On the final kernel

2026-10-09, kernel-only build of PR #608 at 5661f21, the same Turnip
with mesa-008 on both sides.

**Games**, 10 minutes each, flip traces through runemu (Mesa's runs on
the kernel before, whose Mesa path is the same):

| | Frames shown twice | Scanout - target, median / p95 | Presents late / committed after target | Checks failed |
|---|---|---|---|---|
| Super Mario World, Mesa | 35986 of 35988 | 3.88 / 8.82 ms | 339 / 1325 | 0 |
| Super Mario World, kernel | 35963 of 35967 | 3.08 / 4.88 ms | 282 / 311 | 0 |
| Tekken 3, Mesa | 35803 of 35811 | 0.65 / 2.10 ms | 564 / 781 | 1 |
| Tekken 3, kernel | 35781 of 35793 | 0.66 / 1.87 ms | 540 / 587 | 2 |

Tekken 3's failures on the kernel: six phase jumps in the first 2.2 s,
while the grid is still being found as the game boots (Mesa has targets
from the first frame), and two later ones with the plane programmed 4.1
and 2.9 ms after the commit, the display-side kind Mesa's run had too.
No trigger shared a refresh with another, and the run a refresh behind
that the build before had for six minutes did not come back. Twice a
frame came early off the grid, once while booting and once after a
stall of two 18.6 ms frames, which the grid took for a new rate; its
repeat went at once, held for the refresh's end, and added nothing.

**Rate changes in one session**, present-probe `rate:A,B switch=5`,
40 s: after every switch the kernel's count was right two frames on,
and every frame was shown k times from 0 to 5 frames on (Mesa, from its
targets: 0 to 2). The build before kept 30 Hz's count after every switch
to 60 Hz.

**Below 17 Hz without `vblank-rate`** (`--no-hold`): at 12 Hz 345 of
349 frames got all 9 repeats (6 to 8 on the build before), at 15 Hz 436
of 437 all 7.

**Pause and menu**, 100 cycles each through RetroArch's network
commands, both paths: every run ended cleanly, with no DPU or DSI error.
RetroArch keeps presenting while paused, about every 16 ms but 15 to
18 ms apart; the kernel's grid then settles just under two refreshes a
frame and stops repeating, which shows nothing since the paused picture
does not change, and after a resume takes a frame or two to repeat
again, where Mesa, following the targets, does not.

**Power and CPU**, present-probe at 30 Hz (k = 4), no tracing, on
battery, 60 s each, in the order Mesa, kernel, Mesa, kernel:

| | Power, W (sd of 0.5 s samples) | Timer irq/s | All irq/s | Context switches/s | CPU busy, % of one core | present-probe CPU |
|---|---|---|---|---|---|---|
| Mesa | 1.737 (0.093), 1.712 (0.099) | 4270, 4214 | 6393, 6340 | 5713, 5694 | 22.6, 24.2 | 2.13, 2.16 % |
| kernel | 1.620 (0.090), 1.628 (0.109) | 3879, 3962 | 5775, 5866 | 4948, 4953 | 19.9, 20.3 | 1.23, 1.21 % |

About 0.1 W less with the kernel's repeats, at 90 repeats a second.

### Five minutes per rate

The comparison that decided it, run while the switch was being made:
the kernel at 5661f21 with mesa-005 still in the test Turnip, only
`msm.dpu_lfc` toggled. present-probe, 300 s per run, every 600th frame
4 ms late, `tools/display-check --rate`.

| Rate | Repeats | Frames shown k times | Panel on its own | Refresh vs P/k, median / p95 / p99 ms | Scanout - target, median / p95 ms | Checks failed |
|---|---|---|---|---|---|---|
| 60.099 Hz | Mesa | 17999 of 18003 | 2 | 0.002 / 0.006 / 0.007 | 12.33 / 14.59 | 0 |
| 60.099 Hz | kernel | 17997 of 18003 | 6 | 0.002 / 0.006 / 0.007 | 6.88 / 7.38 | 0 |
| 59.94 Hz | Mesa | 17923 of 17955 | 30 | 0.022 / 0.052 / 0.200 | 0.84 / 11.73 | 0 |
| 59.94 Hz | kernel | 17894 of 17955 | 31 | 0.022 / 0.071 / 0.226 | 0.49 / 3.36 | 1 |
| 59.826 Hz | Mesa | 17888 of 17920 | 30 | 0.038 / 0.102 / 0.305 | 0.48 / 10.64 | 1 |
| 59.826 Hz | kernel | 17859 of 17921 | 31 | 0.037 / 0.092 / 0.275 | 0.42 / 2.30 | 0 |
| 50 Hz | Mesa | 14949 of 14977 | 28 | 0.114 / 0.353 / 0.745 | 0.24 / 0.52 | 2 |
| 50 Hz | kernel | 14951 of 14977 | 27 | 0.071 / 0.311 / 0.624 | 0.27 / 0.79 | 0 |
| 40 Hz | Mesa | 11960 of 11982 | 21 | 0.014 / 0.021 / 0.190 | 0.99 / 11.76 | 0 |
| 40 Hz | kernel | 11939 of 11982 | 23 | 0.014 / 0.044 / 0.178 | 0.46 / 3.37 | 0 |
| 30 Hz | Mesa | 8970 of 8987 | 17 | 0.014 / 0.027 / 0.227 | 0.93 / 11.39 | 1 |
| 30 Hz | kernel | 8954 of 8986 | 17 | 0.013 / 0.036 / 0.199 | 0.44 / 2.99 | 0 |

- **The first look holds over five minutes.** Refreshes land as close to
  P/k on both. The kernel shows 16 to 29 more frames off their count,
  about one per late frame: the frame after a late one, shown a refresh
  short so the panel is back on the content's clock. In exchange the p95
  phase is 2.3 to 3.4 ms against Mesa's 10.6 to 11.8, which spends the
  minutes after each late frame a refresh behind.
- **60.099 Hz levels off on both.** Half a frame is the fastest refresh,
  so only a skipped repeat brings the panel back. The kernel held 6.6 to
  7.3 ms behind the targets, 30 s medians, for the whole run; Mesa
  started at 14.6 and drifted to 10.4.
- **Failed checks.** Kernel, 59.94 Hz: two phase jumps of 2.2 ms with no
  cause in the trace. Mesa: at 30 Hz a repeat committed 15.9 ms after it
  was due; at 50 Hz two frames shown three times with the plane
  programmed 2.3 and 3.4 ms after the commit; at 59.826 Hz one jump with
  no cause in the trace.

## The GPU clock: no fence deadline

At a commit, the atomic helper gives each plane's fence a deadline: the
start of the next vblank, from the mode's frame length. msm boosts the
GPU when such a fence is still running 3 ms before its deadline, raising
the clock's floor to twice the current clock for 50 ms
(`msm_fence_set_deadline`, `msm_devfreq_boost`). With AVR the panel waits
in its front porch for the commit, so a frame starts about 0.4 ms after
it and that vblank is always near or past. RetroArch presents right after
its final blit, about 80 us of GPU work, so a commit often went out with
the blit still running, and each such commit boosted. At fixed refresh
Mesa commits at a vblank event, the deadline is about 7 ms away, and the
blit has long finished.

Patch 1108 sets no deadline on a CRTC with `VRR_ENABLED`, so devfreq's
load decides the clock, as it does at fixed refresh. A late frame under
VRR is shown late, not dropped at a vblank.

NFSU on ARMSX2 with the test Turnip (main and mesa-009), on battery,
110 s from 35 s in. The race loads a savestate 25 s in; 3x is ARMSX2's
internal resolution, 2x otherwise. Before is kernel 5661f21 with LFC on,
after is the same kernel with 1108. Frames off their count are those not
shown twice, the savestate load's pause left out.

| Run | Kernel | GPU MHz, mean | At 680 MHz | Mcycles per frame | Boosts | Battery W | Frames off their count | Phase p95, ms |
|---|---|---|---|---|---|---|---|---|
| Intro, VRR | before | 647 | 88% | 0.29 | 1755 | 2.67 | 1 | 0.91 |
| Intro, VRR | after | 401 | 0% | 0.27 | 0 | 2.70 | 3 | 0.83 |
| Intro, fixed | before | 404 | 1% | 0.27 | 255 | 2.76 | 73 | - |
| Intro, fixed | after | 449 | 17% | 0.27 | 761 | 2.74 | 107 | - |
| Race, VRR | before | 522 | 40% | 2.86 | 867 | 4.94 | 29 | 1.74 |
| Race, VRR | after | 455 | 19% | 2.77 | 0 | 4.89 | 43 | 1.44 |
| Race, fixed | before | 455 | 19% | 2.74 | 364 | 4.89 | 75 | - |
| Race, fixed | after | 441 | 14% | 2.74 | 335 | 4.89 | 56 | - |
| Race 3x, VRR | before | 610 | 43% | 4.38 | 375 | 5.70 | 41 | 4.07 |
| Race 3x, VRR | after | 606 | 40% | 4.36 | 1 | 5.77 | 75 | 2.65 |
| Race 3x, fixed | before | 608 | 42% | 4.38 | 163 | 5.60 | 226 | - |
| Race 3x, fixed | after | 616 | 44% | 4.41 | 129 | 5.61 | 155 | - |

- **The boosts are gone, and VRR clocks as fixed refresh does.** The
  work per frame is the same throughout, within 3%.
- **No underclocking under load.** Every run held 59.9 fps or more in
  every 10 s window, and display-check passed every run. The 3x race ran
  at 606 MHz against 610: above 50% load devfreq raises the clock without
  the boost.
- **Frames.** Frames off their count and late presents (1, 104 and 275
  after, against 1, 112 and 280) are within the spread of the unchanged
  fixed-refresh runs between the two batches.
- **Power hardly moves.** The VRR runs are within 0.07 W of before; the
  same fixed-refresh runs repeat within 0.02 W. At light load the clock
  costs little: the intro keeps the GPU busy 3 to 4% of the time, so at
  680 MHz it only idles longer.
- **Fixed refresh still boosts**, 129 to 761 times per run, when a commit
  lands within 3 ms of a vblank. 1108 leaves it as it was.
- **Open:** at 3x, VRR draws 0.10 to 0.16 W more than fixed refresh at
  the same clock, before and after. The deadline does not explain it.

## The launch

Every RetroArch game runs with variable refresh, with no setting to get
right. runemu decides it per launch and exports
`MESA_VK_WSI_DISPLAY_VRR`, which Mesa and setsettings both read. It is 1
on KMS, on a panel that says `vrr_capable` and is the only output (a dock
brings a fixed-rate one), unless the game pins a `display_mode`.
Otherwise it is 0.

- Mesa (`mesa-006`) sets `VRR_ENABLED` in its first mode set, and clears
  it when it lets the CRTC go. 0 clears one left on by a run that
  crashed. Opt-in rather than Mesa's `adaptive_sync` default, because mpv
  and SDL's KMS emulators present through the same backend without
  timing their frames.
- setsettings uses the fastest mode for every game, Sync to Exact Content
  Framerate, vsync off whatever the vsync setting says, and no frame
  delay. The table of a mode at twice each system's rate is for fixed
  refresh.
- RetroArch (`0019`) keeps presents timed under Sync to Exact Content
  Framerate with vsync off. Vsync off would otherwise show each frame
  whenever it was ready. Content that does not fit twice into the
  display's rate is locked to the display for that session: vsync,
  half its rate, audio resampled.

`vrr=0` in `system.cfg`, for everything (`global.`), a system or a game,
turns it off to compare. The fixed refresh path is then as before.

Measured 2026-10-08 through runemu, flip traces:

| | Refreshes | Longest refresh | |
|---|---|---|---|
| Super Mario World, 30 s | 3606, every frame twice | 8.42 ms | `VRR_ENABLED` 0 before, 1 while running, 0 after exit |
| Super Mario World forced onto 119.88 Hz, 20 s | 2398 | 8.46 ms | "does not fit twice", swap interval 2, the core at 59.94 |
| Tekken 3 with `global.vrr=0` | - | - | a `VRR_ENABLED` left on was turned off; 119.652 Hz mode |

## The panel's porches

Variable refresh runs on the fastest mode, 120.198 Hz. Until #623 that mode
had a 142-line back porch where every other mode has 27, and the panel does
not lock to it: it scans its own memory at about 120.14 Hz, and every game
showed a tear every few seconds, all the time at 50 fps. The DPU's CRC saw
every refresh whole, which is why nothing here caught it; a person watching
a moving bar did (`tools/tear-tap`). Patch 1110 gave it the 27 lines of the
other modes, and the beat went, but those were three lines more than the
panel's own 24: it then followed a stretch of only about 0.3 ms, and tore at
50 fps. Patch 1112 puts every mode on the panel's own 998-line timing, which
follows the stretch at 50 fps too. The measurements are in
[REFRESH_RATES.md](PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md).

So a timing check here ends at the DPU. What the panel shows has to be
watched, and the measurements above describe the link: on the wide mode the
panel's own scan sat between them and the eye.

## Do not

Do not write the DPU's timing registers from userspace. Writing
`INTF_VSYNC_PERIOD_F0` on INTF 1 (0xae3600c) with `devmem` while the panel
ran rebooted the Nova, with no record of why. Use mode setting, or the
kernel patch.
