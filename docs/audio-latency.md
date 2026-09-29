# Audio latency: where the milliseconds are

A user measured button-to-sound on the Nova against Android, filming at 240 fps
and counting frames in Premiere: 10-19 frames on PortareOS (42-79 ms) against
10-12 on Android (42-50 ms). The same tests put PortareOS *ahead* on
button-to-screen by about a frame. They also found RetroArch's audio latency
setting would not go below 32 ms without crackling, where Android took 15. The
game was Kirby Super Star, so the path under test was Snes9x at a 32 kHz link.

## Where it ended up

**The setting now goes to 8 ms, which is as low as RetroArch allows.** The
sweep was run downwards to find the breaking point and never found one: at 4
the frontend logs `8 ms setting ... (raised to the minimum)` and runs at 8.
`pw-top`'s ERR column stayed flat on Snes9x and on SwanStation, the core this
tree already documents as having run 55.65 fps with the buffer running dry.

| | `audio_latency` floor, 32 kHz |
|---|---|
| as reported | **32 ms**, crackled below |
| after #422 | ~24 ms |
| after #422 and #428 | **8 ms**, the frontend's own minimum |

The DSP path has stopped being the constraint. Both changes are now read out
of the driver rather than inferred, with `pcm-flags`:

```
info flags, as the driver reports them:
  BATCH                  no          <- #428, patch 1074

at 32000 Hz:  accepted period sizes  320 640 960    <- #422, step 320 = 10.0 ms
at 44100 Hz:  accepted period sizes  448 896        <- #422, step 448 = 10.2 ms
```

`SNDRV_PCM_INFO_BATCH` is what made PipeWire keep an extra period queued, and
it was the largest single term in the budget below. It is gone. The step that
was 480 frames at every rate is now 10 ms of frames at the stream's own rate.

The intermediate measurement, after #422 but before #428, was the same
tester's camera method: **8 to 15 frames at 240 fps, averaging 13** - 33 to
63 ms against the original 42 to 79, with the floor already below Android's
best of 10 frames. The absolute figure has not been re-measured since.

**Still open:** power, since pull mode has the DSP publish its position
continuously and nothing has looked at idle wakeups or suspend; the systems
other than SNES and PlayStation; and whether 8 ms is safe to ship as the
default, which needs the quirk in `020-set_audio_latency` changed and a
migration beside it.

## How it was reasoned about first

Everything below was written before any of it was measured, from the code this
image ships. It is kept because it is what the fixes were aimed at, and it was
right about where the milliseconds were.

## The chain, at the shipped values

### 1. The setting was 32 ms, and it was not this device's number

`packages/hardware/quirks/autostart/020-set_audio_latency` is a ROCKNIX file
and writes the default when the setting is absent. `setsettings.sh`'s
`set_audiolatency` then writes it into RetroArch's `audio_latency` on **every**
launch, so the global setting is what every core runs with and a value changed
in RetroArch's own menu does not survive a relaunch. 32 was chosen for a tree
that also has to boot on an RK3326; nothing picked it here. It is 24 now, with
`migrate_audiolatency_24` in `post-update` moving an install that still sits on
the old default and leaving any value chosen since alone.

### 2. What RetroArch does with the setting

`audio/drivers/pipewire.c`, at the pinned commit `9705e03a`:

* the quantum it asks the graph for is a quarter of the setting, floored at
  128 frames: `buf_samples = latency * rate / 4000`
* its own ring is the whole setting, and dynamic rate control holds it about
  half full
* it logs the budget at init, which is the first thing to read on the device:
  `[PipeWire] 24 ms setting: a … ring (… ms, rate control holds it about half
  full) in front of a requested …-frame quantum (… ms)`

It sizes the ring to hold at least twice the quantum **it asked for**. What it
gets can be different, and it is never told.

### 3. What the graph does with the request

Two things in `src/pipewire/context.c`, neither of them obvious from the config:

* **the quantum bounds are scaled by the link rate.** `min-quantum` is 256 in
  `002-graph-quantum.patch`, but that is 256 *at `default.clock.rate`*, which is
  48000. At another rate all three bounds are rescaled
  (`context.c:1727-1729`), so the floor is 235 frames at 44.1 kHz and 170 at
  32 kHz - **5.33 ms at every rate.** There is no rate-dependent floor.
* **the result is floored to a power of two.**
  `default.clock.power-of-two-quantum` is unset here and defaults to `true`
  (`settings.c:30`), so `flp2()` is the last thing applied
  (`context.c:1756`). A request for 352 frames becomes 256. A request for 288
  becomes 256. A request for 192 becomes 128.

The second is the one that decides the shape. Between about 21 ms and 42 ms at
48 kHz, every setting produces the same 256-frame quantum, so lowering the
setting shrinks RetroArch's ring and leaves the pull it has to service
unchanged:

| setting | rate | asks for | graph runs at | ring, half full | ring / pull | slack |
| --- | --- | --- | --- | --- | --- | --- |
| 32 ms | 48000 | 384 | 256 | 768 | 3.00 | 10.7 ms |
| 32 ms | 44100 | 352 | 256 | 705 | 2.75 | 10.2 ms |
| 32 ms | 32000 | 256 | 256 | 512 | 2.00 | 8.0 ms |
| 24 ms | 48000 | 288 | 256 | 576 | 2.25 | 6.7 ms |
| 24 ms | 44100 | 264 | 256 | 529 | 2.07 | 6.2 ms |
| 24 ms | 32000 | 192 | **128** | 384 | 3.00 | 8.0 ms |
| 16 ms | 48000 | 192 | 256 | 384 | **1.50** | 2.7 ms |
| 16 ms | 44100 | 176 | 128 | 352 | 2.75 | 5.1 ms |
| 16 ms | 32000 | 128 | 128 | 256 | 2.00 | 4.0 ms |

The margin RetroArch believes it has is two pulls. 48 kHz is the rate that loses
it first, because 256 frames is a power of two and the quantum therefore cannot
step down until the request halves: at 16 ms the ring is 1.5 pulls and 2.7 ms
from empty. At 24 ms no rate is under two pulls, which is why 24 is the number.

**Corroboration from the device.** Commit `b2134e956b` recorded that "the graph
ran at 256 frames while RetroArch asked for 352" and read it as `min-quantum`
outvoting the request. `flp2(352)` is 256, so that observation is the
power-of-two flooring, and it is the only reading of the graph quantum anyone
has actually taken here.

### 4. The sink: a 480-frame floor that nothing above it can move

*Superseded by #422 and #428; kept because the mechanism is unchanged and the
numbers below are what the fixes were measured against.*

`q6apm-dai.c` declares `SNDRV_PCM_INFO_BATCH` on both playback and capture, and
constrains `PERIOD_SIZE` and `BUFFER_SIZE` to steps of **480 frames**, with the
comment *"setup 10ms latency to accommodate DSP restrictions"*.

PipeWire's ALSA plugin, `spa/plugins/alsa/alsa-pcm.c` in 1.6.8, then:

* takes the graph quantum as the period, halves it because the device is batch,
  and calls `snd_pcm_hw_params_set_period_size_near` - which the 480-frame step
  rounds back up to 480
* `recalc_headroom()`: `if (state->is_batch) state->headroom += state->period_frames`,
  so **+480 frames**, on the reasoning that a timer-scheduled reader can miss a
  batch device's pointer update
* tops the device up to `threshold + headroom`, that is quantum + 480 frames

Unlike the graph's bounds, this 480 is **not** scaled by rate: it is a driver
constant in frames, so it is 10.0 ms at 48 kHz, 10.9 at 44.1 and 15.0 at 32.
It is the largest single term in the budget and nothing in userspace can move
it.

## The budget

`ring/2 + quantum + (quantum + 480)`, in milliseconds:

| path | ring, half full | quantum | sink | total |
| --- | --- | --- | --- | --- |
| 48 kHz, was 32 ms | 16.0 | 5.3 | 15.3 | **36.7** |
| 48 kHz, now 24 ms | 12.0 | 5.3 | 15.3 | **32.7** |
| 44.1 kHz, was 32 ms | 16.0 | 5.8 | 16.7 | **38.5** |
| 44.1 kHz, now 24 ms | 12.0 | 5.8 | 16.7 | **34.5** |
| 32 kHz, was 32 ms | 16.0 | 8.0 | 23.0 | **47.0** |
| 32 kHz, now 24 ms | 12.0 | 4.0 | 19.0 | **35.0** |
| 32 kHz, 24 ms, with #422 | 12.0 | 4.0 | 14.0 | **30.0** |
| 44.1 kHz, 24 ms, with #422 | 12.0 | 5.8 | 16.0 | **33.8** |

The 32 kHz row gains 12 ms rather than 4, because at 24 ms it is the one rate
whose request falls below 256 and takes the quantum down to 128 - which shrinks
the sink's top-up as well as the quantum itself. That is the path the report
measured.

Then the AudioReach graph, MI2S and the aw88166 amps, none of which is visible
from here. The measurement was 42-79 ms against a 47.0 ms budget for the path
measured, so the rows above account for it and the answer is not hiding in the
DSP.

## What is still open

1. **Why 32 ms was a floor for the reporter is not explained.** By the table
   above, 16 ms at a 32 kHz link leaves the ring two pulls deep, which should
   not crackle. Either something else on that device was late, or the setting
   was not taking effect - and a value changed in RetroArch's menu does not
   survive the relaunch `setsettings` performs. `pw-top`'s ERR column says
   which node, if any.
2. **The 480-frame headroom, which is conditional.** `recalc_headroom()` adds it
   only under `if (!state->disable_tsched || state->resample)`. In IRQ mode
   PipeWire wakes on the period interrupt and knows the pointer exactly, so the
   480 frames drop to `api.alsa.headroom`, which is 0 by default. The other half
   of the guard is already satisfied: the allowed-rates work runs the link at the
   stream's rate, so the sink does not resample. q6apm-dai's period completion
   *is* a DSP event, which is the condition IRQ mode assumes. `wireplumber`'s
   `package.mk` already copies `config/${DEVICE}/*.conf`, and that directory
   does not exist yet; a `monitor.alsa.rules` block setting
   `api.alsa.disable-tsched = true` is where this goes. Worth 10 to 15 ms and
   entirely untested.
3. **The 480-frame step itself.** See below.

## The 32 kHz link is not the problem

It costs about 2 ms against 48 kHz, not the 13 an earlier draft of this document
claimed: the fixed 480-frame headroom is worse in milliseconds at a lower rate,
but at 24 ms the 32 kHz request is the one that gets a 128-frame quantum, and
that nearly cancels it.

| Snes9x at 24 ms | total |
| --- | --- |
| 32 kHz, as shipped | 35.0 ms |
| 44.1 kHz | 34.5 ms |
| 48 kHz | 32.7 ms |

So dropping 32 kHz for 44.1 or 48 buys half a frame at 240 fps and gives up the
gentler conversion `AUDIO_SAMPLE_RATES.md` chose it for. Not worth it. Keep the
rate; the milliseconds are in item 2 above and in the step below.

## The ULL graph: not a port, and probably not the first move

AudioReach is not something to bring to Linux - it is already the framework
mainline uses, `sound/soc/qcom/qdsp6`, and `q6apm-dai` opens graphs out of the
same topology blob Android does, by id. What Android has that this does not is a
*graph configured for small buffers*, plus a path that does not impose 10 ms on
the way in. Three pieces, in increasing order of how much is unknown:

1. **The driver constants, which are not per-graph.** The 480-frame step and
   `SNDRV_PCM_INFO_BATCH` are applied in `q6apm_dai_open` to every substream,
   whatever graph is behind it. The comment says the step accommodates "DSP
   restrictions", which is a claim about the DSP that may only be true of the
   default graph. **Done, and the claim was false.** #422 replaced the fixed
   step with 10 ms of frames at the stream's own rate - 320 at 32 kHz, 448 at
   44.1, 480 unchanged at 48 - and the DSP starts the graph as before. Measured
   on the device with a SNES game running: `period_size: 320`, and the
   pathological `Sink rate` warning RetroArch used to log (-17451 ppm of 32000)
   is gone, replaced by -50 ppm. #428 then clears `SNDRV_PCM_INFO_BATCH` in
   push-pull mode and moves the topology to `SH_MEM_PULL_MODE`, which should
   take the headroom too; merged, not yet run.
2. **Whether the shipped blob even has a low-latency graph.** Answerable by
   inspection: `tplg-playback-rates.py` already walks the type-7 PCM blocks and
   found only `MultiMedia1 Playback` and `MultiMedia2 Playback`. Android's
   blobs usually expose many more frontends, a low-latency one among them, so a
   two-frontend topology is a sign this one may not carry it. The blob is not in
   this tree - it arrives with `extra-firmware` - so this needs a build or a
   device.
3. **Authoring a graph, if it is absent.** This is the wall.
   `AUDIO_SAMPLE_RATES.md` already records that the available AudioReach `.m4`
   source does not reproduce the shipped binary, which is why the rate work
   edits the blob in place. Adding a frontend and a graph is a great deal more
   than patching three fields, and there is no way to regenerate the blob to
   check the result against.

So: yes in principle, and the honest order is 1, then 2, and only then consider
3. Item 1 may make the rest unnecessary.

## The experiment that settles it

Read the two lines that state what was actually negotiated. From the journal,
the sink's own summary:

    journalctl -b | grep -E 'period frames|headroom'

which prints `buffer frames … period frames … periods … headroom … batch:1
tsched:…`. **`period frames 480` and `headroom 480` confirm section 4; anything
else means the model above is wrong and the rest of this document with it.**

Then RetroArch's, which states its half of the budget in milliseconds:

    grep 'ms setting' /storage/.config/retroarch/logs/*

And the device's view, while a game is playing:

    cat /proc/asound/card0/pcm0p/sub0/hw_params     # period_size, buffer_size
    pw-top                                         # QUANT on the sink and on RetroArch

`pw-top`'s QUANT on RetroArch's node against the sink's is the direct check on
section 3: a 24 ms setting at 48 kHz should show 256 even though RetroArch asked
for 288, and 128 at a 32 kHz link.

Sweep the setting, one run each, listening for crackle and watching `pw-top`'s
ERR column. `set_setting global.audiolatency <ms>` then relaunch, because
`setsettings` rewrites the config at launch:

    for ms in 24 21 16 12 8; do ... ; done

Do it on a 48 kHz core and on Snes9x, because the two rates fail in different
places: 48 kHz thins out at 16 ms, 32 kHz not until 8.

Re-measure end to end the way the report did - 240 fps, count frames from the
D-pad to the waveform - because every number above is a budget and only the
camera says what came out of the speaker.
