# Latency per system

How long the Nova takes, per system, from RetroArch reading the pad to the
first line of the resulting frame on the panel. With variable refresh (see
[variable refresh](VARIABLE_REFRESH.md)) the display adds about a millisecond
once a frame is ready, so what is left is the emulator's: its core time, its
GPU work, and the budget RetroArch's 0018 keeps for both.

## What is measured

Per frame, from a trace:

- **Read**: RetroArch's last input poll before the core hands it the frame
  (`input_driver_poll`, the poll whose state the frame was emulated with).
- **First line**: the vblank timestamp of the refresh that first showed the
  frame, from Mesa's commit marker (mesa-007) paired with its flip and vblank
  by `tools/display-check`.
- **Core**: `retro_run` up to the core's video callback.
- **GPU**: the GPU's own busy time per frame, from
  `drm_msm_gpu/msm_gpu_submit_retired`.
- **Budget**: 0018's target minus the frame's start: the 94th percentile of
  the last 64 ready times and 1 ms.

Not included: the game's own lag (frames between reading the pad and drawing
the result; preemptive frames remove one), the pad's latency, and the scan
down the panel, about 3.6 ms more to the middle of the screen.

The runs used RetroArch 9705e03 with this tree's patches and a test-only
patch that writes one `ralat` trace marker per frame (frame start, poll,
video callback, ready, budget, target) when `RALAT` is set; it is not in the
image. The rest was the image as of nightly 20261009 with the kernel of
#616 (no fence deadline under VRR) and Mesa main fdbc48d with this tree's
WSI patches, VRR on, `tools/display-trace` with the `drm_msm_gpu` events,
110 s per run, the window 45 to 105 s after the first flip, attract or title
scenes, the image's cores.

## Measured, 2026-10-09

| System (core) | Preemptive frames | Read to first line, median / p95 ms | Core per frame, ms | GPU per frame, ms | Budget, ms | Notes |
|---|---|---|---|---|---|---|
| Genesis (Genesis Plus GX), Streets of Rage 2 | off | 4.91 / 5.69 | 0.63 | 0.28 | 4.1 | |
| | on | 4.89 / 5.58 | 0.68 | 0.28 | 4.1 | |
| Game Boy (Gambatte), Tetris | off | 5.81 / 6.54 | 0.15 | 2.20 | 5.2 | gameboy.slangp |
| | on | 5.83 / 6.50 | 0.16 | 2.19 | 5.2 | |
| GBA (mGBA), Wario Land 4 | off | 5.73 / 6.44 | 0.66 | 1.05 | 5.0 | lcd-grid-v2 |
| | on | 7.83 / 8.74 | 0.84 | 3.21 | 7.1 | GPU at 125 MHz in this run, not explained |
| PlayStation (SwanStation), Tekken 3 | off | 7.06 / 8.17 | 1.80 | 0.95 | 6.3 | 32 late frames |
| | on | 5.89 / 7.88 | 2.02 | 0.94 | 5.4 | 22 late frames |
| Super Nintendo (Snes9x), Super Mario World | off | 11.95 / 12.32 | 0.77 | 3.76 | 8.0 | crt-guest-advanced |
| | on | 10.70 / 11.07 | 0.91 | 3.76 | 8.2 | |
| Saturn (Ymir), Daytona USA | - | 7.46 / 10.50 | 5.81 | 0.80 | 12.2 | read mid-frame; 62 late frames |
| Dreamcast (Flycast), Virtua Tennis | - | 13.12 / 17.44 | 0.95 | 4.57 | 11.7 | 112 late frames |
| Nintendo 64 (parallel_n64), Super Mario 64 | - | 28.43 / 33.76 | 2.75 | 0.85 | 15.2 | read after the frame; 133 late frames |
| PlayStation 2 (ARMSX2), NFSU | - | 2.80 / 3.00 | 0.02 | 0.67 | 2.2 | RetroArch's part only |

Late frames are frames ready after their target, out of about 3590.

- **Preemptive frames cost almost nothing on the 2D systems**: 0.01 to 0.22 ms
  more core time per frame, for a frame (16.7 ms) of the game's own lag
  taken off. The image ships them off for every system.
- **A shader's GPU time is latency.** The frame is timed to when it is
  ready, and at this load the GPU stays at its 401 MHz floor, so Snes9x's
  CRT shader (3.8 ms) and Gambatte's LCD shader (2.2 ms) sit in the path
  whole. At fixed refresh they were hidden behind the wait for a vblank.
- **The budget's margin** over the median ready time is 1.5 to 6.3 ms,
  largest where frame times vary: Saturn, Dreamcast, N64.
- **N64 reads the pad after the frame**: parallel_n64's poll comes from the
  game's controller read late in `retro_run`, so the frame it affects is the
  next one. Super Mario 64's intro also has heavy frames (core p95 14 ms).
- **Saturn reads mid-frame**, 5.6 ms into it, which is why its read to
  first line is shorter than its frame start to first line (13.1 ms).
- **PS2**: ARMSX2 emulates on its own threads and `retro_run` returns a frame
  they finished earlier, so its internal queue is not in this number.
- **Not measured**: GameCube (Dolphin hangs after a FIFO error in this
  build); NES, arcade and Neo Geo (no ROM on the test device).

### The SNES shader

Super Mario World again, preemptive frames off, `snes.shaderset=none` against
the image's `crt/crt-guest-advanced.slangp`:

| Shader | Read to first line, median / p95 ms | Render and fence, ms | Budget, ms | Target to first line, ms | GPU per frame, ms | Late frames |
|---|---|---|---|---|---|---|
| crt-guest-advanced | 11.95 / 12.32 | 4.59 | 8.04 | 3.99 | 3.76 | 3 |
| none | 6.28 / 6.51 | 0.93 | 4.42 | 1.77 | 0.27 | 5 |

The shader is 3.6 ms of the budget, and the read to first line drops by
5.7 ms. The other 2.2 ms is the panel's wait after the target, which was 4.0
and 2.5 ms in the two shader runs: at 60.099 Hz each frame is shown twice at
the panel's fastest refresh, so that wait moves between runs on its own.
Frames were ready 5.5 ms into the 16.6 ms period with the shader, so it fits;
the question is only what it costs.
