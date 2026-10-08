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
rate (see the launch below).

## Showing a frame more than once

The repeat lives in Mesa's KMS backend (`mesa-005`). RetroArch presents
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

The general form is LFC in the DPU driver, which would cover every
client, not only timed VK_KHR_display presents. It waits until AVR has
had more testing: #586.

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
longest frame AVR holds is 1676 lines, 12.49 ms, and the idle check above
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

## Do not

Do not write the DPU's timing registers from userspace. Writing
`INTF_VSYNC_PERIOD_F0` on INTF 1 (0xae3600c) with `devmem` while the panel
ran rebooted the Nova, with no record of why. Use mode setting, or the
kernel patch.
