# NeoCD (Neo Geo CD)

The reference system for the PortareOS performance methodology (#666): a
workload cheap enough that any host overhead shows. The question is not
whether Metal Slug runs at full speed, but how cheaply the Nova reproduces
the Neo Geo CD correctly and where the remaining host cost is.

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
- Games are `.chd` only (#669); `nova-push` converts on the way in.
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
  mask 0 so the 320 columns are exactly 4 panel pixels each; the 224 lines
  are 4.286 rows each, and the lines shader draws a beam per console line at
  sub-pixel positions rather than darkening fixed rows. Integer 4x (1216x896
  with the mask, square pixels, a 32-row bar top and bottom) was the
  alternative; the faithful geometry won.
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
| `neocd_cpu_overclock` | 100% | Same. |
| `neocd_aspect_ratio` | 4:3 DAR | The tube's geometry; see Presentation. |
| `neocd_overscan_h` | 0 | Exactly 4 panel pixels per column at full width. |
| `neocd.integerscale` | 0 | Full-screen 4:3. |
| `neocd_region` | Japan | |
| `audio_out_rate` | 44100 | See Audio. |
| run-ahead / preemptive frames | excluded (`NO_RUNAHEAD` in setsettings) | Predates #667; to be re-evaluated with the capture (goal 5 first). |

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

## What is already good

- Audio runs at the CD's own rate with no conversion, 8 ms, no xruns.
- The emulation costs about a tenth of one middle core; nothing in the core
  is a hotspot worth touching before the host side is.
- Presentation follows the core's rate exactly (2 x 59.5999) under VRR.
- Run-to-run spread of 1 % makes small changes measurable.

## Room for improvement

- The X3 and the A510 cluster run at their maximum for RT threads that are
  ~1 % busy. First candidate: lower `kernel.sched_util_clamp_min_rt_default`
  (0, then a middle value), same capture, three replays, audio constraint
  enforced.
- Checkpoint divergence at `z80TimeSlice`: find out whether it is the
  recording's checkpoint being taken mid-slice or a real nondeterminism;
  the core declares its states deterministic.
- Frametime logging in the benchmark runner.
- GPU floor at 401 MHz: a 320x224 frame scaled to 1280x960 does not need it;
  measure what it buys.
- Preemptive frame: one frame, same capture, once goal 5 holds.

## Open questions

- Does the Z80 time slice depend on the host (audio buffer state) or only on
  the frame?
- What keeps the GPU at 401 MHz, and is it wanted for this system?
