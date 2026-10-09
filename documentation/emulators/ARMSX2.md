# ARMSX2 (PS2)

## What runs

- `armsx2-lr` 2.7.2, the ARMSX2 libretro core (`armsx2_libretro.so`), in
  RetroArch. It replaced the SDL standalone in #473.
- Recipe: `packages/emulators/libretro/armsx2-lr/`.
- Patches:
  - `000-fix-arm-compilation.patch`: page and cache-line size when
    cross-compiling.
  - `001-libretro-pace-to-the-frontend.patch`: one clock, queue depth, audio
    ring.
  - `002-libretro-pin-threads-by-core-tier.patch`: thread pinning and a total
    core order.
  - `003-libretro-clamp-pinned-threads.patch`: a utilization floor on the
    pinned threads.
  - `004-libretro-apply-gamedb-blending.patch`: blending accuracy raised to
    the GameDB's per-game recommendation.
- Settings live in `/storage/roms/bios/pcsx2/inis/armsx2-libretro.ini`, not
  `PCSX2.ini`. The core rewrites the keys the patches force on every load, and
  keeps everything else. That includes values left behind by an earlier build:
  delete the ini before comparing builds.

## Presentation

The core has no swapchain. It tells the GS its window is surfaceless, and
`GSDeviceVK` creates none. Every PS2 vsync still runs a full present pass
(`DoBeginPresent`/`EndPresent`), into one of three private backbuffers. These
are sized to the upscaled frame, widened to the display aspect: about
1280x960 at 2x. The core submits it, and `VKLibretro::PublishFrame` hands the
image to `retro_run`, which passes it to RetroArch with `set_image`.

RetroArch draws that image into its own swapchain:

- KHR display context, 2 images, FIFO.
- Swap interval auto, so 2 at 119.88 Hz.
- Timed presents (RetroArch patch 0014). The log shows
  `Timed presents: swap interval 2, one present a frame, 16.683 ms apart.`

The core's own pass is about 1.2 MP per frame, cheap on the Adreno 740.

Every GS submit takes RetroArch's `queue_lock` (`VKLibretro`'s
`vkQueueSubmit` wrapper). RetroArch holds that lock across
`vkQueuePresentKHR`, because the core gives it the same queue for presenting.
Not measured whether Turnip's display backend blocks inside the present.

## Vulkan driver

PS2 runs on the image's Mesa, like every other system. From build 208
(`006c681`) until the Mesa bump to 26.3.0-devel it ran on the ARMSX2 team's
own Turnip build instead (`armsx2-turnip`, #497), selected for the
`armsx2` core with `VK_DRIVER_FILES`. That package is gone.

**What the ARMSX2 build changed on the Adreno 740:** one patch, "tu: flush
before a declared feedback-loop draw on a7xx". A draw whose state declares
an attachment feedback loop gets the flush a colour-write to fragment-read
barrier would have produced, so ARMSX2's GS can drop its own barrier there.
Its other patches touch Adreno 6xx or 610 only, or Wayland, and it is built
on Mesa main at `e3a986f0`.

**How the image carries it:**
- Mesa is 26.3.0-devel, main of 2026-10-09 (`fdbc48df`), and `mesa-009`
  adds the flush, on only for the engine named `ARMSX2`, which the core passes
  RetroArch through libretro's Vulkan context negotiation. Every other
  application keeps stock behaviour.
- ARMSX2 trusts a driver to order a declared loop only when `driverInfo`
  carries its packs' `git-axfl2-` tag. armsx2-lr patch 005 takes Turnip as
  fix generation 2 without the tag. The core's GS messages in the RetroArch
  log (not `exec.log`) read:

      VK: self-read road = in-pass, driver-ordered, declared feedback loop (driver fact) [texbarrier=on intile=off layout=on ordersOverlap=claimed]
      VK: driver claims feedback-loop fix generation 2 (driverInfo 'Mesa 26.3.0-devel'); declared-loop ordering TRUSTED.

- With the image's Mesa, PS2 also gets our `mesa-002` (the panel profile
  stays applied) and `mesa-006` (variable refresh); ARMSX2's build had
  neither, so PS2 ran at fixed refresh with RetroArch set up for variable
  refresh, and 4.9% of frames were shown for 1 or 3 refreshes instead of 2.

**Measured before the switch** (2026-10-09, NFSU's intro, 90 s per run, GPU
clock every 0.25 s from 30 s on; a test build of 26.3.0-devel at
`e3a986f0`, ARMSX2's base, with `mesa-009`, tagged so the unpatched core
trusted it):

| Driver | Display | GPU clock, mean |
|---|---|---|
| ARMSX2's Turnip | fixed, `ps2.vrr=0` | 401 MHz, the floor, in both runs |
| 26.3.0-devel + `mesa-009` | fixed, `ps2.vrr=0` | 401 MHz, the floor, in both runs |
| ARMSX2's Turnip | as launched (VRR asked, never on) | 494, 483, 489 MHz |
| 26.3.0-devel + `mesa-009` | variable refresh | 575, 587 MHz |
| image's Mesa 26.2.3, barriers | variable refresh | 535, 556 MHz |

On the same display the two drivers are the same. Variable refresh itself
costs PS2 GPU clock on this scene; why is open.

**The NFSU race of #503, from a savestate** (2026-10-09, blending High, the
state loaded 25 s in through RetroArch's network command, 110 s measured
from 35 s; the player's car stands at the start while the others race,
so every run shows the same frames; the 26.3.0-devel build is `fdbc48df`
with `mesa-009`):

| Driver | Display | fps per 10 s window | GPU clock, mean |
|---|---|---|---|
| ARMSX2's Turnip | as launched (VRR asked, never on) | 59.9-60.0 | 488, 475 MHz |
| 26.3.0-devel + `mesa-009` | fixed, `ps2.vrr=0` | 59.9-60.0 | 456, 450 MHz |
| 26.3.0-devel + `mesa-009` | variable refresh | 59.9-60.0 | 522, 520 MHz |
| image's Mesa 26.2.3, barriers | fixed, `ps2.vrr=0` | 59.9-60.0 | 592, 586 MHz |

No run dropped a frame. With `mesa-009` the image's Mesa needs a little
less GPU clock than ARMSX2's Turnip and a quarter less than 26.2.3 with
ARMSX2's barriers, the setup that fell to 49.9 fps in #503's race with a
car being driven. Variable refresh costs about 70 MHz on the same driver.

## Pacing: one clock

Before 001 the core reported no refresh rate, so the VM never synced to a host
and slept to its own timer at the guest rate. RetroArch meanwhile called
`retro_run` on the panel's clock. `retro_run` takes whatever frame the GS
published, or repeats the last. The GS blocks in `PublishFrame` until that
happens. Two clocks raced.

001 makes RetroArch the only clock:

- **Refresh rate.** At load the core asks for RetroArch's target refresh
  (`GET_TARGET_REFRESH_RATE`) and divides it by the swap interval RetroArch
  picks for the announced 59.94 fps (`round(refresh / fps)`, `runloop.c`). That
  is the rate `retro_run` runs at, and it goes into the window info as the
  host refresh rate.
- **Settings.** `VsyncEnable`, `SyncToHostRefreshRate` and `UseVSyncForTiming`
  are on. `SkipDuplicateFrames` is off, because vsync timing needs every frame
  presented, and PCSX2 defaults it to on.

The VM then runs the guest at the host's rate and skips its sleep throttle.
Pacing comes from the hand-off: the GS blocks until `retro_run` takes the
frame. In this core, "vsync" costs nothing on the GPU, since there is no
swapchain to wait on. It is only the switch that lets the hand-off pace
emulation.

Check it engaged, in `/var/log/exec.log`:

    Refresh rate: Host=59.940059hz Guest=59.939998hz Ratio=1.000000 - can sync and using vsync for pacing

and in the RetroArch log:

    Pacing to the frontend: 119.880 Hz refresh, 59.940 Hz frames.

PAL (50 fps) is outside PCSX2's 5% sync window at 59.94. It falls back to the
sleep throttle, as before 001.

### Queue depth (`VsyncQueueSize`)

A frame counts as queued until the GS has finished with it, and the GS
finishes only once `retro_run` has taken it (`MTGS.cpp`, `PostVsyncStart`).
So the queue depth is how many frames the EE may run ahead of the screen.

| Depth | EE runs ahead | Input to frame taken (estimate) | Cost |
|---|---|---|---|
| 2 (PCSX2 default) | 2 frames | ~3 frames | most lag |
| 1 | 1 frame | ~2 frames | |
| 0 (current) | none | ~1 frame | EE, GS and hand-off run in turn within 16.7 ms |

0 is what the standalone ran. In this core it is more expensive than in the
standalone: the standalone's present did not wait for anything, while here
the EE waits for `retro_run` itself. Plan: start at 0, step up only if it
cannot hold full speed.

## Audio

- SPU2 mixes at 48 kHz into the Null backend's ring. `retro_run` empties the
  ring on every call (`PullFrames`) and hands it to RetroArch.
- The Null backend has no time-stretch. `CreateStream` ignores the flag for
  it, although the log prints `stretching enabled`.
- `BufferMS` (64) is the ring's capacity, not latency: nothing aims for a fill
  level, and the ring is emptied every frame. What is in it at a drain is what
  piled up since the last one, about one frame at queue depth 0. Long stalls
  do not grow it, because the EE is parked at the hand-off.
- Overflow drops 64-frame chunks without a log line (`LOG_UNDERRUN` is
  compiled out). The only window in which the EE runs unpaced is
  `retro_serialize`/`retro_unserialize`, about 1 to 2 frames.
- RetroArch's `audio_latency` is real latency: a buffer kept filled. Do not
  raise it to test pacing; it hides the underruns being measured.
- Below full speed the core makes less than real-time audio and RetroArch
  underruns. Bad sound in this core has so far always been slowdown.

## CPU and core mapping

SoC layout, caches and the governor findings are in
[../CPU_ISOLATION.md](../CPU_ISOLATION.md).

| Core | Design | Runs |
|---|---|---|
| 7 | X3, 1 MB L2 | EE ("CPU Thread") only |
| 3 | A715 | VU1 ("MTVU") |
| 4 | A715 | GS |
| 5, 6 | A710 | RetroArch main thread, audio, the core's helper threads |
| 0-2 | A510 | system, IRQs (`irqaffinity=0-2`) |

How it gets there:

- **Process mask.** `ps2.cores=frontend` makes runemu start RetroArch under
  `FRONTEND_CORES` (`taskset -c 5-6`, quirk `040-affinity`). Every thread
  starts on the A710s.
- **Hot threads.** The core then pins EE, VU and GS itself (002,
  `EnableThreadPinning`) to the first three entries of its processor list.
  The list is ranked as the kernel ranks cores: `cpu_capacity`, else
  `cpuinfo_max_freq`, else cpuinfo's own clock. Ties go to the newer design
  within a tier, then to the core number. On the Nova: 7, 3, 4, 5, 6, 0, 1, 2.
- **Why not cpuinfo's clock:** it reads 0 for every core here. The first
  version of 002 ranked by it and fell back to the core number, putting EE,
  VU and GS on the A510s. Those cores are outside the game's cpuset, so the
  kernel refused the pinning and all three stayed on the process mask, cores
  5-6.
- **Helper threads.** "ISO Decompress" starts while the CDVD opens, before
  the pinning, and stays on the process mask. A thread started later by a
  pinned thread would inherit that thread's single core; `coremap-check`
  catches that.
- **Mesa background threads.** Mesa's shader-cache threads
  (`retroar:disk$N`, nice 19) reset their own mask to all cores. They are
  background work and allowed.

Why: each core has a private L2, and all eight share the L3. A thread that
moves refills its L2 from L3, and EE's recompiled code and hot state are the
largest working set. Sampled before 002, GS ran on all five big cores within
3 s.

Caveat from ARMSX2's own source (`VMManager.cpp`, Android path): VU1 pinned
to an A7xx ran about 1.4x slower than on the X3 in VU-bound games (God of War
II). NFSU is EE-bound (EE 37%, VU 23% at full clocks). VU-bound games may
want VU on the X3: test some before calling the layout settled.

### Test

`coremap-check` (in `/usr/bin`) samples the running core's threads and fails
if EE, MTVU or GS are allowed anywhere but 7, 3 and 4. It also fails if any
other non-niced thread is allowed on those cores. Run it during a game:

    ssh root@<device> coremap-check

It has caught two failures so far:

- On the build before 002 (2026-10-01): every thread allowed on 3-7, GS
  seen on cores 3, 4, 5, 6 and 7.
- On the first nightly with 002 (`1a3d441`, 2026-10-02): EE, MTVU and GS
  confined to 5-6 with the rest of the process, after the pinning to cores
  0-2 was refused.

## Settings and why

| Setting | Where | Why |
|---|---|---|
| `VsyncEnable`, `SyncToHostRefreshRate`, `UseVSyncForTiming` on, `SkipDuplicateFrames` off | 001 | one clock |
| `VsyncQueueSize = 0` | 001 | least lag; step up if needed |
| `BufferMS = 64` | 001 | ring capacity, ~3.8 frames |
| `EnableThreadPinning = true` | 002 | fixed cores, warm L2 |
| `ps2.cpugovernor=performance` | `system.cfg`, migration `ps2-cpu-layout` | 40 to 59.7 fps, see measurements |
| `uclamp.min` = the pinned core's `cpu_capacity` on EE, VU, GS | 003 | full clock for the hot threads under schedutil; no effect while the governor is `performance` |
| `ps2.cores=frontend` | `system.cfg`, migration `ps2-cpu-layout` | RetroArch on the A710s |
| `ps2` in `NO_RUNAHEAD`, `NO_REWIND` | `setsettings.sh` | both save a state every frame; a PS2 state is 68 MB, and each one switches pacing off and on |
| `armsx2_upscale = 2x` | `retroarch-core-options.cfg` | as the standalone ran (#15) |
| `armsx2_blending_accuracy = "Automatic"` | `retroarch-core-options.cfg`, patch 004 | Basic, raised per game to the GameDB's `recommendedBlendingLevel`, within its `maximumBlendingLevel`. Upstream only warns about the recommendation, on an OSD the core does not show, so every game ran at Basic. An explicit level is kept as chosen. `exec.log` shows `GameDB: Raising blending accuracy from 1 to the recommended 3` |
| Turnip flushes before a declared feedback-loop draw | Mesa `mesa-009`, for the engine `ARMSX2` only; armsx2-lr patch 005 trusts it | ARMSX2's GS drops its own barriers there, as on its team's Turnip (#497) |

## Measurements

| Date | Build | Game, scene | Change | Result |
|---|---|---|---|---|
| 2026-10-01 | 001, queue 0 | NFSU, in race | schedutil | 40.3-43.1 fps; EE 18-22%, GS 18-26%: threads idle most of the frame |
| 2026-10-01 | 001, queue 0 | NFSU, in race | cores 3-7 on performance, by hand | 55.8 fps over the switch, then 59.7; by ear "much better" |
| 2026-10-01 | 001, queue 0 | NFSU, first minutes of a session (intro FMV, menus) | schedutil | 57.1-59.1 fps, EE 26-49%; by ear, FMV sound good |
| 2026-10-02 | nightly `1a3d441` (001, 002 first version, performance, isolation) | NFSU, menus | EE, VU, GS on 5-6 | 59.6-59.8 fps |
| 2026-10-02 | nightly `1a3d441` | NFSU, in race | EE, VU, GS on 5-6 | 47.2 fps; EE 25%, GS 25%, VU 19% at full clocks, so waiting on each other |
| 2026-10-02 | nightly `1a3d441` | NFSU, in race | moved live with `taskset -p`: EE 7, VU 3, GS 4 | 52.2 over the move, then 58.8, then 59.9 for three windows (~90 s); EE 23-28%, GS 24-34%, VU 17-23% |
| 2026-10-02 | nightly `1a3d441` | Time Crisis II, gameplay | EE, VU, GS on 5-6 | 59.0 fps, near saturation: EE 63%, VU 52%, GS 35% (about 1.5 of the 2 cores) |
| 2026-10-02 | nightly `1a3d441` | Time Crisis II, gameplay | moved live: EE 7, VU 3, GS 4 | 59.7-59.9 fps; EE 38-53%, VU 28-42%, GS 18-29%, the same work in less thread time |
| 2026-10-02 | build 208 (`006c681`): ARMSX2's Turnip (barriers off), pinning, floor | Time Crisis II, gameplay | driver changed from the row above | 59.9 fps in all four windows; EE 46-57%, VU 34-48%, GS 27-35%, GPU 10-15%. No gain and no loss; the game barely reads back in-pass, the only thing the driver speeds up |
| 2026-10-03 | build `6f8d1b3`: blending Automatic (NFSU raised to High), ARMSX2's Turnip | NFSU, race, 5 min | run A | race windows 59.2, 59.5, 59.8, 59.9, 59.8, 59.9 fps; GPU busy 34-41 %, GPU clock mean 356 MHz (floor not in effect, #502); max zone 72 °C; fan at its first step |
| 2026-10-03 | same, `ps2.vulkandriver=system` | NFSU, race, 5 min | run B: the image's Mesa, ARMSX2's barriers back on (`barrier-ordered`) | race windows 56.2, 58.7, 59.0, 59.4, 57.6, 59.9, 49.9, 57.4 fps; GPU busy 43-55 %, GPU clock mean 572 MHz, at 680 MHz in half the samples (floor 401 MHz); max zone 74 °C; fan up to its second step |

## Open questions

- What Automatic blending costs where it raises the level. NFSU at High held
  59.2-59.9 fps in a race on ARMSX2's Turnip; on the image's Mesa 26.2.3 with
  barriers the same level cost more (49.9-59.9). Other games raised by the
  GameDB are unmeasured.

- The race with a car being driven, on the image's Mesa with `mesa-009`.
  From the savestate (see Vulkan driver) it held 59.9-60.0 fps at less GPU
  clock than ARMSX2's Turnip. Read-back-heavy games (the author's: Indiana
  Jones, Stuntman, Splashdown, WRC 3) are unmeasured.
- Why variable refresh raises PS2's GPU clock on the same driver: NFSU's
  intro 575-587 MHz mean against 401 at fixed refresh, the race 520-522
  against 450-456.

- Queue depth 0 against 1 with pinning and `performance`: fps, repeated
  frames, audio gaps in a 15 s capture.
- A VU-bound game (God of War II) with VU on an A715 against VU on the X3.
- Whether RetroArch's present blocks while holding `queue_lock` on Turnip's
  display backend.
- RetroArch segfaults on exit, after `Releasing host memory for virtual
  systems...` (seen twice in `exec.log`).
- Whether 003's clamp can replace the `performance` governor. Patch 003 sets
  it: EE 1024 on the X3, VU and GS 657 on the A715s. It has no effect until
  PS2 runs under schedutil. Test by setting `ps2.cpugovernor=schedutil` in
  `system.cfg`, then compare against `performance` on the same scene: fps,
  repeated frames, audio, and drain, clocks and temperature from `perf-probe`.
  The default changes only if schedutil with the clamp holds what
  `performance` does. `exec.log` shows `EE thread util clamp min 1024` when
  it is set.
- Texture barriers: the standalone forced them off
  (`OverrideTextureBarriers = 0`); the core's automatic turns them on, and a
  barrier is expensive on a tiler. Not measured yet (ROADMAP).
- PAL games do not sync to 59.94 and run on the sleep throttle.
