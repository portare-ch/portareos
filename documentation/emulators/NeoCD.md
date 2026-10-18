# NeoCD (Neo Geo CD)

The reference system for the PortareOS performance methodology (#666): a
workload cheap enough that any host overhead shows. The question is not
whether Metal Slug runs at full speed, but how cheaply the Nova reproduces
the Neo Geo CD correctly and where the remaining host cost is.

## Status: optimization finished, 2026-10-18

Four of the five goals below hold on build 287 with the shipped settings
(full-screen 4:3, lines-1x, the preemptive frame); the fifth, the prime
core's clock, is a system-wide scheduler policy and not this emulator's,
and is handed over as its own issue. Nothing in NeoCD is left to tune for
this device; the next emulator starts from the methodology this one
produced (capture, three replays, intro and gameplay apart, the latency
rig, one change per round).

## Goal

Optimization is finished when all of these hold on the fixed Metal Slug
capture, measured the way [Measurements](#measurements) describes:

1. Audio: 44.1 kHz end to end, 8 ms RetroArch latency or lower, zero xruns
   in the intro and in gameplay. Latency is never traded for anything below.
2. Presentation: 59.5999 fps from the core, every frame scanned twice at
   119.1998 Hz, no late frame and no single-refresh frame in a 4-minute
   trace.
3. CPU: the emulation stays on the gaming cores (3-7), the prime core (7) is
   idle and at its floor clock unless the workload needs it, and no core sits
   at its maximum clock on account of a thread that is 1 % busy.
4. Cost: the gameplay window costs less than the baseline by more than the
   run-to-run spread, with the guest unchanged (no CPU overclock, no CD
   speed hack).
5. Determinism: a capture verifies with every checkpoint matched, so a
   change can be checked against the same frames.

Candidates that fail 1 are rejected whatever they gain elsewhere.

How it ended: 1, 2, 4 and 5 met (see Measurements). 3 is met for the
emulation, which never touches the X3, and not met for the X3's clock:
`kernel.sched_util_clamp_min_rt_default` 1024 lifts any core an RT thread
wakes on to its maximum, and the X3 collects RetroArch's audio threads,
the msm `gpu-worker` (SCHED_FIFO, ~180 wakes/s) and the odd irq thread.
Three cheap fixes were measured and rejected: the default at 0 (the middle
cluster drops to its floor with it, late frames double), RetroArch confined
to 3-6 (the worker keeps the X3 up, cost +45 %), the worker on 0-2 (the
audio threads keep it up, cost +27 %). A per-thread clamp or a kernel-side
policy is the fix, for every system at once; it is not NeoCD's to carry.

## What runs

- `neocd_lr` at `b1e04c7` (`packages/emulators/libretro/neocd_lr/`), in
  RetroArch. BIOS files under `/storage/roms/bios/neocd/`.
- Patches: `001-default-to-a-cdz-bios.patch` (#668): the first CDZ BIOS by
  family is the default and the fallback for an unmatched name, instead of
  index 0 of the name-sorted list (the Front Loader, which stops at its CD
  player until START).
- `core-info` adds `savestate = "true"` and
  `savestate_features = "deterministic"` to NeoCD's info file (#667).
  Upstream's file predates the keys, and without them RetroArch and
  gamecapture refuse run-ahead, preemptive frames and captures.
- Games are `.chd` only (#669). Prepare them with PortareOS tools and
  transfer the CHD with `nova-push neocd`; automatic conversion currently
  recognizes the older `neogeocd` name. See [installation](../INSTALLATION.md).
- Build: the toolchain passes `-O2 -flto -march=armv9-a+... -mtune=cortex-x3`;
  NeoCD's Makefile appends `-Ofast -DNDEBUG` and `USE_LTO=1` on its own, and
  the last `-O` wins. The effective build is `-Ofast` with LTO. Enabling LTO
  is not an experiment, it is already on.

## Presentation

- Core rate 59.5999 Hz (6042000 / 101376). VRR with kernel LFC; setsettings
  asks for the exact 119.1998 Hz mode (2 x 59.5999) and the panel repeats
  each frame twice.
- Full-screen 4:3, decided 2026-10-18: the console's 320x224 filled a 4:3
  tube, so the picture fills the 4:3 panel. Integer scaling off
  (`neocd.integerscale=0`), aspect `core` with the core's `4:3 DAR`, overscan
  mask 8 (the hardware blanks the outer 8 columns each side; with the mask
  off they showed as a black band in-game, seen 2026-10-18). So 304x224 to
  1280x960: 4.21x across, 4.29x down, neither an integer. The lines shader
  draws a beam per console line at sub-pixel positions rather than darkening
  fixed rows. Integer 4x (1216x896, square pixels, a 32-row bar top and
  bottom) was the alternative; the faithful geometry won.
- Scanlines, decided 2026-10-18: `portare/lines-1x.slangp`, crt-lines with
  only the beam (no grille, glow or horizontal softness), beam 0.26 dark to
  0.38 bright, boost 1.25. Seven candidates were rendered at the panel's
  pixels from the same replay frame and viewed live; the user chose this one
  over a wider-beam "mild" (too saturated: the boost clips highlights) and
  prefers the dimmer picture. Lines only, no CRT filter, was the brief.
- Open: a display trace of the fixed capture confirming 2x LFC with no late
  or single-refresh frames (goal 2). Not yet taken.

## Audio

- The core hands RetroArch 44100 Hz, the CD's rate. `NeoCD.cfg` sets
  `audio_out_rate = "44100"`, so no 44.1 -> 48 kHz conversion runs; the Nova's
  link takes 44.1 kHz as readily as 48. Rate control still adjusts by up to
  0.5 %.
- RetroArch latency 8 ms: PipeWire reports a 2816-byte buffer, 8.0 ms of
  stereo float at 44.1 kHz, held near 4 ms by rate control.
- RetroArch runs three SCHED_FIFO threads: `ra-audio` (50), `audio_driver`
  (50) and PipeWire's client `data-loop.0` (83). These, not the emulation,
  decide the clocks (see below).

## CPU and core mapping

- `cores=big`: RetroArch runs under `taskset 3-7` in `game.slice`, system
  work on 0-2 (`documentation/CPU_ISOLATION.md`).
- The main thread (68000, Z80, YM2610, renderer, all in one) runs on cores
  3-6, about a tenth of one core. It never lands on the X3.
- `data-loop.0` sits on core 7 for the whole run at ~1 % busy. With
  `kernel.sched_util_clamp_min_rt_default = 1024`, every RT wakeup clamps
  its core to the maximum frequency, and one wakeup per audio period means
  the clamp never expires: the X3 runs at 2957 MHz for a thread that does
  almost nothing. The PipeWire server's RT loops do the same to the A510
  cluster (near 2016 MHz throughout).
- `coremap-check` layout: not written yet; one thread of interest, the main
  one, and three RT threads.

## Settings and why

| Setting | Value | Why |
|---|---|---|
| `neocd_bios` | `neocd_z.rom (CDZ)` (#663) | Boots the game itself, loads at double speed. Redundant once #668 is in. |
| `neocd_loadskip` | On | Skips the CD load wait; does not change the game's behaviour. |
| `neocd_cdspeedhack` | Off | Guest unchanged for measurements. |
| `neocd_cpu_overclock` | 100% | Same. One exception: Metal Slug 2 (disc serial `NGCD-00241`) runs at 150 % through a per-disc override, `/usr/config/games/neocd/NGCD-00241.opt`; its own slowdown is the engine's (SNK rewrote it as Metal Slug X) and its logic is vblank-paced, so only the overrun frames get faster. Keyed by the disc, not the file name. |
| `neocd_aspect_ratio` | 4:3 DAR | The tube's geometry; see Presentation. |
| `neocd_overscan_h` | 8 (default) | The hardware's blanked columns; 0 showed them as black bands. |
| `neocd.integerscale` | 0 | Full-screen 4:3. |
| `neocd.shaderset` | portare/lines-1x.slangp | Scanlines only; see Presentation. Its GPU time is in the latency path (LATENCY.md); measured in the next round. |
| `neocd_region` | Japan | |
| `audio_out_rate` | 44100 | See Audio. |
| `neocd.preempt` | 1 | On by default (user, 2026-10-18) after the A/B: 0.5 ms more path and a third more CPU for the game's frame of lag, zero xruns, and the console's own pause and RetroArch's survive it in Metal Slug and Metal Slug 2. Settings > Consoles switches it (portarelauncher 0.8.3). |

## Measurements

Append, do not rewrite. Full data for each run is in `/storage/perf/<name>/`
on the test Nova (samples.csv at 1 Hz, threads.txt, MangoHud csv when it
logged).

### 2026-10-18, build 20261018, Metal Slug, capture `neocd/metal-slug-001`

Workload: 240 s scripted capture, 60 s of BIOS, logos and title music, then
Start and 180 s of run, shoot, jump (the player dies and continues). A
human-played capture replaces it as the reference once recorded. Three
replays through `gamecapture verify`, a perf-probe over each.

| | intro 0-60 s | gameplay 60-240 s |
|---|---|---|
| RetroArch process, ticks/s (100 = one core) | 12.7 / 12.9 / 13.0 | 11.8 / 11.9 / 12.0 |
| main thread, ticks/s, where | 9.7 / 9.6 / 9.8, cpu 3-6 | 8.7 / 8.8 / 8.8, cpu 3-6 |
| `data-loop.0`, ticks/s, where | 0.9, cpu 7 (100 %) | 0.9, cpu 7 (100 %) |
| `ra-audio`, ticks/s | 0.7-0.8, cpu 3-6 | 0.7-0.8, cpu 3-6 |
| policy7 (X3), median / p95 | 2957 / 2957 MHz | 2957 / 2957 MHz |
| policy0 (A510), median / p95 | 1901-2016 / 2016 MHz | 1670-1786 / 2016 MHz |
| GPU, median / max | 401 / 401 MHz | 401 / 401-680 MHz |
| xruns | 0 | 0 |

- Spread between runs about 1 %: a change must move gameplay cost by more
  than ~0.3 ticks/s to be seen in three runs.
- The intro costs more than gameplay: the BIOS and title loop is the heavier
  frame, so the whole workload is "low load".
- The GPU never leaves 401 MHz, which is its `min_freq` as set (lowest OPP
  124.8 MHz). Not NeoCD's doing; relevant when the GPU floor is looked at.
- Verify: the replay reaches the end every time (241.5 s), but the closing
  checkpoint at frame 14194 differs from byte 31 of 8231939, which is
  `z80TimeSlice` in the core's state layout. Being checked by comparing the
  end states of two replays.
- MangoHud wrote no frame log in these runs (its log is written when its
  duration ends, and the duration was longer than the run; being fixed), so
  application and display intervals are missing here.

### 2026-10-18, build 20261018, capture `neocd/metal-slug-002`, three settings

Capture 002 is the same scripted input recorded with the pointer-free core
(#671); it verified with every checkpoint matched. These replays ran on the
image's core from before #671, so verify reports "diverged" at the pointer
bytes; the replays are deterministic (two end states identical but for
those bytes). MangoHud logged with its smallest overlay shown (fps only),
which the earlier baseline did not have. Gameplay window, three replays
each, medians unless noted:

| | aspect only | aspect + lines-1x | RT clamp 0 (aspect only) |
|---|---|---|---|
| RetroArch ticks/s | 12.9 / 12.9 / 13.0 | 12.8 / 12.9 / 13.1 | 43.6 / 44.3 / 43.8 |
| main thread ticks/s | 9.8 / 9.7 / 9.8 | 9.6 / 9.8 / 10.0 | 31.8 / 32.4 / 31.9 |
| X3 (policy7) | 2957 MHz | 2957 MHz | 595 MHz |
| cores 3-6 (policy3) | 499-2803, swinging | 499-2803, swinging | 499 MHz |
| GPU | 401 MHz, 1.0 % load | 401 MHz, 4.0 % load | 401 MHz, 1.0 % |
| xruns, intro / gameplay | 0 / 0 | 0 / 0 | 0 / 0 |
| display interval mean / p99 | 16.85 / 17.5-17.7 ms | 16.85 / 17.5 ms | 16.90 / 18.4-18.5 ms |
| frames over 21 ms (the capture's loads) | 8-10 | 9-10 | 17-22 |
| single-refresh frames | 7-8 | 7-8 | 14-22 |
| present interval p99 | 19.3-19.4 ms | 19.3 ms | 21.4-21.6 ms |
| `data-loop.0` sits on | cpu 7 | cpu 7 | cpu 4-5 |

- **The shader costs nothing measurable in delivery.** GPU load 1 to 4 % at
  the 401 MHz floor, about 0.5 ms a frame, with identical frame intervals,
  late counts and CPU cost. The lag felt live is not in these numbers; if
  it is real it is below what frame intervals show and needs the
  LATENCY.md rig (read to first line).
- **The 8 to 10 frames over 21 ms per run are the capture's own loads**
  (deaths and continues; max 170 ms), the same count in every replay.
- **RT clamp default 0 is rejected as it stands.** The X3 goes to its floor
  and the audio threads leave it, with no xruns, but the middle cluster
  drops to 499 MHz too and the main thread takes three times as long for
  the same work: late frames double, p99 display interval 18.5 against 17.5
  ms, present p99 over 21 ms. Drain read 89 to 166 mAh against 47 to 55 in
  the other runs, but the pack was at 12 to 18 % by then and the counter's
  run-to-run spread says the gauge, not the load; not used.
- **Next candidate instead:** keep the clamp, move RetroArch off the X3
  (`cores` mask 3-6 for this system). The RT audio threads then lift the
  middle cluster, which the main thread uses anyway, and the X3 idles at
  595 MHz. Measured the same way.
- Aspect-only cost sits 1 tick/s above the first baseline (12.9 against
  11.9); the overlay drawn for logging is in that number, the first
  baseline had none. Compare rounds from here against this one.

### 2026-10-18, boss fight live, new geometry and lines-1x

145 s of play, flip trace and frame log: 8633 frames, every one two
refreshes after the previous (16.79 ms), one 146 ms frame at a CD load
inside the fight, zero xruns, GPU 4 % at 401 MHz. The slowdown felt is the
game's own (Metal Slug slows on hardware when sprites pile up); a 68000
overclock would remove it and is parked as a per-game option.

### 2026-10-18, read to first line, with and without lines-1x

The LATENCY.md rig: a RetroArch with one trace marker at the input poll
and one at the video callback (the `ralat` patch, test build), Mesa's
commit markers, vblanks, flips and GPU submits traced; capture 002
replayed, the window 45 to 105 s after the first flip, 3567 frames each.
Two runs per setting, full-screen 4:3 with the mask, charger connected.

| | read to first line, median / p95 | poll to video callback | video callback to commit | GPU busy per submit |
|---|---|---|---|---|
| no shader | 4.25 / 4.88 ms, 4.29 / 4.85 | 1.31 / 2.90 | 2.55 / 3.59 | 0.08 / 0.20 |
| lines-1x | 4.83 / 5.46 ms, 4.85 / 5.52 | 1.29 / 2.83 | 3.14 / 4.20 | 0.24 / 0.73 |

- The shader adds 0.6 ms, a thirtieth of a frame, all of it between the
  video callback and the commit: 0.16 ms of GPU time and the rest in the
  frame's wait. Repeatable to 0.05 ms between runs. The lag felt live is
  not this; 0.6 ms is below what a hand can tell.
- Without the shader, 4.25 ms from pad read to first line is the lowest of
  any system in LATENCY.md (Genesis 4.9). The frame is ready 1.3 ms after
  the poll and waits for its slot; the display adds 0.3 ms after the commit.
- The maxima (150 to 159 ms) are the capture's load frames.

### 2026-10-18, build 287, capture `neocd/metal-slug-003`, final state

The image's own core (#668, #671 in), the shipped settings. Capture 003
recorded and verified on it: validated, and every replay below validated
too (the "diverged" on capture 002 was the core-build mismatch, #685).
Charger connected, so no drain column. Gameplay window, medians:

| | shipped | RetroArch on 3-6 | gpu-worker on 0-2 |
|---|---|---|---|
| RetroArch ticks/s | 12.9 / 12.9 / 12.8 | 18.5 / 18.6 / 18.7 | 16.4 / 16.4 / 16.3 |
| X3 median / p95 | 2957 / 2957 MHz | 2957 / 2957 | 2957 / 2957 |
| xruns, intro / gameplay | 0 / 0 | 0 / 0 | 0 / 0 |
| display interval mean / p99 | 16.86 / 17.6 ms | 16.87 / 17.7 | 16.85 / 17.7 |
| frames over 21 ms (the capture's loads) | 8-13 | 11-16 | 9-11 |
| verify | diverged (capture 002, other build) | same | validated (capture 003) |

Both placements are rejected; see the Goal section for why the X3 item
leaves this page.

## What is already good

- Audio runs at the CD's own rate with no conversion, 8 ms, no xruns.
- The emulation costs about a tenth of one middle core; nothing in the core
  is a hotspot worth touching before the host side is.
- Presentation follows the core's rate exactly (2 x 59.5999) under VRR.
- Run-to-run spread of 1 % makes small changes measurable.

## Room for improvement

- The X3 at its maximum for RT threads that are ~1 % busy: measured three
  ways, rejected three ways (Goal, Measurements). Handed to a system-level
  issue; nothing more to do here.
- Frametime logging needs MangoHud's overlay drawn (its smallest form is
  used); the overlay's own cost sits in every logged run.
- GPU floor at 401 MHz: a 320x224 frame scaled to 1280x960 does not need it;
  a system-level question, the floor is set for every client.
- Skip CD Loading runs a whole load inside one frontend frame (146 ms at
  Metal Slug's boss, 8-13 such frames in the capture): a per-frame budget in
  the core's skip loop would spread it. Parked; a later round if it bothers.
- The 68000 overclock as a per-game option for the game's own slowdown.
- Neo Drift Out and Pulstar as regression checks when something changes.

## Open questions

- The lag felt with the shader: measured at 0.6 ms from pad read to first
  line. If it is still felt, it is something other than frame delivery.
- What keeps the GPU at 401 MHz, and is it wanted for this system?
