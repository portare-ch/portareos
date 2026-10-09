# SwanStation (libretro)

PlayStation. Measured on the Retroid Pocket Nova; #495 holds the discussion.

## What runs

- Package `swanstation-lr`, libretro/swanstation at `b6c30a7`, under RetroArch.
- Patches:
  - `001`: an NTSC line is 3412.5 ticks.
  - `002`: frontend run-ahead states keep VRAM on the GPU (see Pacing).
- Renderer Vulkan, resolution scale 4x, from `retroarch-core-options.cfg`.

## Presentation

The 119.652 Hz mode, two swapchain images, swap interval 2: one present a
frame, 16.715 ms apart, timed by the driver (RetroArch patch 0014). Integer
scaling for this core only (`SwanStation.cfg`): with overscan cropping the
active area is 320x240, so 4x fills the 1280x960 panel exactly.

## Pacing

Without a preemptive frame the core holds every frame on its vblank (E3 in
the test plan).

**Preemptive frames** (PRMPT in Settings > Consoles, `psx.preempt=1`, off by
default). RetroArch saves a state every frame and, when the input changed,
loads it back, runs the core twice and saves again. SwanStation's
`retro_serialize` took the full savestate path every time. Its VRAM readback
downsamples the 4x VRAM to native and then waits for the GPU to finish
everything queued, the frame's 4x rendering included. On a load, the native
copy is uploaded again. So the emulation thread sat idle at 13-30% of a
core while frames missed their vblank, and a faster GPU only shortened the
wait.

Patch `002` uses what DuckStation does for its own run-ahead. For states
taken under `RETRO_SAVESTATE_CONTEXT_RUNAHEAD_SAME_INSTANCE`, VRAM is copied
GPU to GPU, into a texture per frontend buffer. The CPU never waits, and the
4x content survives the rollback. Normal savestates are unchanged. The fast
path is off while "software renderer for readbacks" is on, because that
renderer keeps a second VRAM in CPU memory.

With the patch the core runs twice on a press, so its thread gets busier
(25-36%). Under schedutil its cluster often sat at 500-1000 MHz, so
`runemu.sh` sets `performance` on the CPUs and the GPU while PRMPT is on
for the PlayStation. Without the preemptive frame the defaults hold every
frame, so nothing changes there.

## CPU and core mapping

One hot thread, RetroArch's main thread running the core. It runs in
`game.slice` on cores 3-7 like every emulator (`CPU_ISOLATION.md`), with the
A510s left to the system. At 13-36% of a core it does not need its own core,
so there is no pinning beyond that.

## Settings and why

| Setting | Where | Why |
|---|---|---|
| Vulkan, 4x | `retroarch-core-options.cfg` | the upscale; costs nothing measurable here |
| `video_scale_integer = "true"` | `SwanStation.cfg` | 320x240 at 4x is the panel exactly |
| `run_ahead_enabled = "false"` | `SwanStation.cfg` | second-instance run-ahead would need a second Vulkan context; preemptive frames are the other flag |
| `audio_out_rate = "44100"` | `SwanStation.cfg` | the SPU's rate; no resampler in the path |
| `psx.preempt=0` | `system.cfg` | off by default like every console |
| `performance` CPU and GPU with PRMPT on | `runemu.sh` | see Pacing |

## Measurements

Tekken 3, fights with buttons mashed, MangoHud frametimes. Missed means a
frame at or above 25.07 ms, the target plus one refresh.

| Date | Build | Change | fps | Missed | p99 |
|---|---|---|---|---|---|
| 2026-09-28 | `fd20d52` | no preemptive frame (E3 reference) | 59.8 | 0 | 19.70 ms |
| 2026-10-03 | `a694ce5` | PRMPT, unpatched, schedutil, GPU 401 | 53.9 | 8.3/s | 30.7 ms |
| 2026-10-03 | `a694ce5` | PRMPT, unpatched, performance, GPU 401 | 53.3 | 10.1/s | 29.3 ms |
| 2026-10-03 | `a694ce5` | PRMPT, unpatched, performance, GPU 680 | 59.0 | 8.7/s | 27.8 ms |
| 2026-10-03 | `a694ce5` + patch 002 | PRMPT, schedutil, GPU 401 | 59.6 | 3.8/s | 26.7 ms |
| 2026-10-03 | `a694ce5` + patch 002 | PRMPT, performance, GPU 401 | 59.8 | 2.2/s | 25.7 ms |
| 2026-10-03 | `a694ce5` + patch 002 | PRMPT, performance, GPU 680 | 59.8 | 0.5/s | 24.96 ms |

The patched rows used a core built in a Debian container (gcc 14, no LTO),
copied over the shipped one. No visual glitches were seen on a rollback.
Each run's phases were consecutive in one session, so how hard the buttons
were mashed differs a little between rows.

## Open questions

- The last 0.5 missed vblanks a second, against none without PRMPT.
- The GPU at maximum without `performance` on the CPUs was not measured
  with the patch, so the CPU half may not be needed.
