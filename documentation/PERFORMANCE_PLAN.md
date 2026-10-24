# Gaming performance: measurements and next experiments

Reviewed 21 October 2026. Change one thing, replay the same workload, and
compare results beyond the run-to-run spread. Current per-emulator decisions
and measurements live in [emulator notes](emulators/README.md); earlier
standalone Flycast investigations are in the [bug history](BUG_HISTORY.md).

## Current baseline

- Games already default to cores 3–7 in `game.slice`; system services and
  unbound workqueues use 0–2 during gameplay. PS2 pins EE to the X3 and VU/GS
  to the A715s, with its frontend on 5–6. Verify with `coremap-check`; see
  [CPU isolation](CPU_ISOLATION.md).
- The gaming GPU floor is already 401 MHz (`gpuperf`), restored on exit.
  The earlier proposal to raise it from the idle floor has been implemented.
- RetroArch, the launcher and Steam use integer-multiple VRR within
  65–120.198 Hz on the built-in panel. DP Adaptive-Sync uses the sink's
  range and selected mode, with a floor of at least 65 Hz and partial device
  coverage. Steam is capped at 60 fps; hakuX and mpv use fixed refresh.
  No vsync or BFI setting is available. See [variable refresh](VARIABLE_REFRESH.md).
- Flycast and Dolphin run as libretro cores. Standalone backend settings,
  `start_flycast.sh`, and sway experiments no longer apply.
- RetroArch defaults to an 8 ms audio request with a 3 ms quantum floor.
  Shared-memory playback, native link rates and graph tuning are already in
  the image. See [audio latency](AUDIO_LATENCY.md).
- NeoCD tuning is finished. Its measurements expose remaining host policy
  costs, especially real-time threads holding high clocks on lightly used cores.

## Record a comparable run

Use a fixed scene or a validated `gamecapture` workload. Capture verification
must match the core build used to record it; a mismatch is not evidence that
an optimization broke determinism. Keep ROM, BIOS, core, shader, scaling and
input sequence fixed, and retain intro/loading and gameplay as separate windows.

Enable MangoHud before launching, on the Nova:

```sh
. /etc/profile
set_setting portareos.mangohud.enabled 1
```

To record frame intervals, configure MangoHud logging as described in the
[debug tools guide](DEBUG_TOOLS.md#mangohud-on-screen-statistics-and-frame-logs).
Showing the overlay alone does not start a log. With the game and its
recording running:

```sh
perf-probe baseline-01 240
cat /storage/perf/baseline-01/summary.txt
```

Use a new label for each run. `perf-probe` writes `/storage/perf/<label>/`:

| File | What it establishes |
| --- | --- |
| `env.txt` | Kernel command line, CPU/GPU bounds and governors, forced PipeWire metadata and any legacy emulator configs found |
| `samples.csv` | Once-per-second CPU clocks, including middle and prime clusters, GPU clock, temperature, battery charge, emulator CPU ticks and xrun counters |
| `frametimes.csv` | Newest non-summary MangoHud CSV, when available; confirm it belongs to this run |
| `summary.txt` | Available clock, thermal, charge, xrun and frame-interval summaries; gawk is needed for full percentile processing |

The probe does not save every current RetroArch setting or start MangoHud
logging. Save the launched RetroArch config, core options, relevant
`system.cfg` overrides, image/core identifiers and capture metadata alongside
the run. Forced PipeWire metadata is not a substitute for the running sink's
rate and quantum: record those with `pw-top`.

Run each candidate and its baseline at least three times. Compare
`application_interval_ms` (between presents) with `display_interval_ms`
(between frames reaching the panel); blank display timing is missing data.
Keep p95/p99, late/repeated-frame counts, xruns and CPU cost. A mean FPS alone
hides hitches. Watch temperature and clock drift during longer runs, and
measure drain on battery; the gauge cannot establish drain while charging.

For display scheduling use `display-trace` and `display-check`. For pad poll
to first scanline use the latency trace markers; see
[latency per system](LATENCY.md). Neither is physical button-to-screen latency.

## Next experiments

### Real-time threads and clock floors

NeoCD's main emulation thread avoids the X3, yet the prime core stays at
2957 MHz for mostly idle real-time audio/GPU threads. The default RT clamp
is 1024. Three measured shortcuts failed: setting the default to zero made
late frames worse; restricting RetroArch to 3–6 or moving the GPU worker to
0–2 increased CPU cost and left the X3 high. Do not repeat them as untested
fixes; [NeoCD](emulators/NeoCD.md) holds the numbers.

Test per-thread clamping or a kernel policy that lets lightweight RT work
scale without slowing the emulation threads. Compare clocks, CPU cost,
xruns, read-to-first-line latency and delivered frames on both light and
heavy cores. Keep PS2's performance governor until schedutil with its
thread clamps matches the recorded performance.

### GPU floor and shader cost

Compare the 401 MHz gaming floor with lower available frequencies per
system, keeping the renderer and shader fixed. Do not raise the ceiling as
a first response to a lightly loaded GPU. Save original values and restore
them after each run; check the launcher's idle floor after exit.

A shader's GPU work is latency on the timed-present path. Compare presets
with both delivery and latency traces, not utilization alone. The SNES CRT
shader and handheld LCD shaders already have measured costs in
[LATENCY.md](LATENCY.md); NeoCD's scanline shader adds about 0.6 ms in its
recorded test. Preserve the chosen geometry and appearance when evaluating
an alternative.

### Flycast regression and Steam validation

Replay Tony Hawk's Pro Skater under the current Flycast core before carrying
the standalone stutter forward. If it reproduces, trace the current
RetroArch audio and presentation paths, without editing removed backend
configs. Its intended 30 fps is not itself a slowdown.

Run a real Steam game on the final kernel/gamescope combination. Verify the
60 fps ceiling through focus changes and Steam's frame-rate overrides,
check repeat cadence and late frames, and return to the launcher. The
existing probe tests do not establish that game-level result.

## Acceptance

Keep a change only when the same validated workload shows an improvement
larger than run-to-run spread while audio latency, xruns, frame delivery,
controls and suspend/resume remain acceptable. Record rejected experiments
as well as successful ones. Restore experimental settings after measuring;
shared defaults need evidence from every affected class of emulator.
