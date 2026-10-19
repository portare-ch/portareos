# Genesis / Mega Drive (Genesis Plus GX)

The second system through the PortareOS performance methodology (#691),
after [NeoCD](NeoCD.md): a fixed Thunder Force IV capture, three replays
per configuration, the intro and the gameplay window apart, one change per
round. The question is not whether the game runs at full speed, but how
cheaply the Nova reproduces the Mega Drive correctly and where the host
cost is.

## Status: baseline established, 2026-10-19

The capture validates, three replays agree within 5 %, and every frame of
the four minutes reaches the panel twice. Two decisions are the user's
before this moves on: scanlines (Genesis ships none today) and the
reference recording (the attract loop stands in until a human-played Strite
segment exists). Nothing has been tuned yet; nothing measured so far says
anything needs to be.

## Goal

Optimization is finished when all of these hold on the fixed capture,
measured the way [Measurements](#measurements) describes:

1. Audio: 44.1 kHz end to end, 8 ms RetroArch latency or lower, zero xruns
   in the intro and in gameplay. Latency is never traded for anything below.
2. Presentation: 59.9227 fps from the core, every frame scanned twice, no
   late frame and no single-refresh frame in a 4-minute trace.
3. CPU: the emulation stays on the gaming cores (3-7), and no core sits at
   its maximum clock on account of a thread that is 1 % busy.
4. Cost: a candidate costs less than the baseline by more than the
   run-to-run spread, with the guest unchanged (no 68000 overclock: the
   game's own slowdown is part of the reference).
5. Determinism: a capture verifies with every checkpoint matched.

Where it stands: 1, 2 and 5 hold on the baseline. 3 holds for the
emulation and not for the X3's clock, the system-wide RT clamp issue
(#687) NeoCD found. 4 has no candidate yet.

## What runs

- `genesis-plus-gx-lr` at `aa74d79` in RetroArch. Thunder Force IV (Japan),
  `.md`, SHA-256 `1950560594416d2bba700c05c6ce21591647c59863fa4afe2d10f871f290679d`.
- Patch `001-deterministic-savestates.patch`: the core's state carried 56
  host pointers (YM2612 slot tables and channel connections, the Z80 irq
  callback) and a load kept two timing values of whatever ran before it
  (the 68k bus-refresh phase, recomputed by `system_reset()` before the
  saved cycle count is restored; the VDP FIFO timestamps, never saved or
  cleared). Two replays of one capture differed only in the pointers; the
  recording differed from every replay in work RAM from 30 s on, because
  the game advances its RNG in an idle loop whose length those timings
  decide. No state format change.
- RetroArch patch 0027 logs the differing ranges of a diverged checkpoint
  (first eight, both sides' bytes, the total): the shape of the difference
  is what told the pointers (two bytes at an 8-byte stride) from the RNG
  (the starfield's object table).
- Considered and dropped: a RetroArch-side reload of the just-written
  state at record start, so recording and playback both run on a loaded
  machine whatever the core. It was built and recorded fine for Genesis
  and NeoCD, but with the core fixed the stock RetroArch validates
  (capture 008), so the cause is fixed where it is.
- Core-reported geometry alternates 320x224 and 256x224 (the game uses both
  H40 and H32); aspect 1.306. Audio 44100 Hz from the core.

## Presentation

- Core rate 59.9227 Hz (53693175 / 896040). VRR with kernel LFC; under VRR
  setsettings hands RetroArch the panel's fastest mode (120.198 Hz) and
  `vrr_runloop_enable` paces to the core. The flip trace shows each frame
  scanned twice: 2 refreshes between 14996 of 15004 flips, the exceptions
  at launch and after the quit, plus one 3-refresh frame at 104 s in one of
  three runs.
- Scaling as shipped: `genesis.integerscale=1`, `genesis.ratio=4/3`: 4x
  down (896 of 960 lines), 3.74x across (1196 of 1280), a 32-row bar top
  and bottom.
- Scanlines: none today (no `genesis.shaderset`), unlike NES, SNES, Saturn,
  PlayStation and NeoCD. Four candidates were captured from the GPU output
  during the Strite demo for the user to choose from: none, `portare/lines-1x`
  (NeoCD's), `portare/crt-240-1x` (Saturn's), `crt/crt-guest-advanced`
  (NES/SNES's). Main-thread cost 10.2 / 10.7 / 11.2 / 12.0 ticks/s; the GPU
  stays at its 401 MHz floor for all four.

## Audio

- 44100 Hz from the core, PipeWire sink at 44.1 kHz; RetroArch logs a
  2816-byte buffer, 8.0 ms, held near 4 ms by rate control. Zero xruns in
  every run.

## CPU

- The main thread (68000, Z80, VDP, YM2612, PSG, all in one) runs on cores
  3-6 at 7.7 ticks/s; RetroArch as a whole 10.4-10.9 ticks/s, 11 % of one
  core. The middle cluster sits at its 499 MHz floor for most of the run.
- The X3 is at 2957 MHz throughout for PipeWire's `data-loop.0` and the RT
  clamp (#687), as on NeoCD. Not this emulator's to fix.
- The GPU never leaves 401 MHz; the probe sees it power-collapsed (125 MHz
  reported) for stretches of the demo.

## Settings and why

| Setting | Value | Why |
|---|---|---|
| `genesis_plus_gx_overclock` | 100 | Guest unchanged; the game's slowdown is the reference. |
| `genesis_plus_gx_ym2612` | mame (ym2612) | Production FM core; Nuked is the optional comparison in #691. |
| `genesis_plus_gx_region_detect` | auto | Japan cartridge, NTSC. |
| `genesis.integerscale` | 1 | As shipped; see Presentation. |
| `genesis.ratio` | 4/3 | As shipped. |
| `genesis.preempt` | 0 shipped | Measured at 0 and 1: 7.7 vs 8.0 ticks/s on the main thread, the capture validates either way. |
| `genesis.shaderset` | (none) | Decision pending; see Presentation. |

## Measurements

All on build 20261018 (BUILD_ID 55e0c74), kernel 7.2.11, on the charger,
with the patched core above; captures 007 and 008 validate with the stock RetroArch. Capture
`genesis/thunder-force-iv-japan-007`: 240 s from launch with no input, the
Sega and Tecnosoft screens and the title (0-55 s), the game's own Strite
demo (55-115 s), the high-score table, and the loop again. Intro window
0-55 s, gameplay window 55-240 s. Scripts: `gen-record.sh`, `gen-replay2.sh`,
`gen-batch.sh` in `/storage/perf` on the Nova.

| Run | RetroArch ticks/s (gameplay) | xruns | display mean / p99 ms | late flips |
|---|---|---|---|---|
| baseline 1 | 10.8 | 0 | 16.688 / 17.30 | 1 (3 refreshes, 104 s) |
| baseline 2 | 10.8 | 0 | 16.688 / 17.25 | 0 |
| baseline 3 | 10.9 | 0 | 16.688 / 17.32 | 0 |
| preempt 1 | 10.9 | 0 | 16.688 / 17.29 | 0 |

A frame is 16.688 ms at 59.9227 Hz; the display mean matches it to the
microsecond.

Captures 001-006 of the same loop diverged at every checkpoint before the
core patch: first differing byte 32786, work RAM 0xFF8002. Preemptive
frames on or off, and a save-and-load before the recording started, made
no difference; the differing ranges (RetroArch patch 0027 logs them) showed
the title's starfield at other positions, the game's RNG. Two replays
differed from each other only in the 112 bytes of the pointers.

## Open

- Scanline preset: the user's pick from the four candidates.
- Human-played Strite reference, from a savestate at the stage start, 240 s.
- Section 9 of #691: uclamp alternative, Nuked FM comparison, background
  interference. None started.
