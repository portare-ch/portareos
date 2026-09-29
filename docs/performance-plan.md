# Gaming performance: what to try, and how to know

Every experiment below is one change, one run, one number. The point of the
harness is that nobody has to remember what was set at the time.

## Measuring

`perf-probe <label> [seconds]` writes `/storage/perf/<label>/`:

* `env.txt` the governors, frequency floors and ceilings, the kernel cmdline,
  the PipeWire quantum and rate, and the emulator's own config. Recorded once,
  because a number nobody wrote down is a run nobody can repeat.
* `samples.csv` CPU and GPU clocks, temperature, charge and xrun count at 1 Hz.
* `frametimes.csv` copied from MangoHud when the run had logging on.
* `summary.txt` medians, p95, p99, max temperature, drain, xruns.

Frametimes are the number that matters and they come from MangoHud, so launch
with it enabled:

    set_setting portareos.mangohud.enabled 1

Then, with the game running:

    perf-probe baseline 60

Take a baseline before changing anything. **p99 frametime is the metric**, not
mean fps: the complaint is variance, and a mean hides exactly that.

## Part 1: general performance

Ranked by evidence against cost. The first two are free to try.

### 1. Emulators are not pinned to the big cluster

`irqaffinity=0-2` sends every interrupt to the three A510 little cores.
Emulators get `taskset` only when the `cores` setting is set, and nothing sets
it by default, so the emulation thread roams onto the same cores that are
servicing every IRQ on the system.

    set_setting dreamcast.cores big        # taskset -c 3-7

Pass: p99 frametime drops. Watch `cpu_big_khz` in samples.csv to confirm the
work actually moved.

### 2. The GPU decays to its floor between bursts

Observed: 125 MHz at rest, brief 680 MHz spikes under load, back to 125.
`simple_ondemand` ramps after the work has arrived, so every burst is measured
against a clock chosen for the idle before it.

Pinning `performance` was already tested and did not fix the flycast stutter,
so this is a responsiveness change rather than a fix for that. Raise the floor
rather than the ceiling, which costs far less idle power:

    D=/sys/devices/platform/soc@0/3d00000.gpu/devfreq/3d00000.gpu
    cat $D/available_frequencies
    echo <mid-opp> > $D/min_freq

Pass: p99 frametime drops and `temp_c` max does not rise more than a couple of
degrees. If it holds, wire it into the per-game `gpuperf` setting rather than
globally, so it applies while gaming and not at the menu.

### 3. The GPU ceiling is 680 MHz and nothing raises it

`bin/gpu_overclock` exists and would set `max_freq` to 1000000000, and nothing
in the tree calls it. Whether the device tree's 680 MHz is a thermal decision
or an untouched default is unknown.

    gpu_overclock enable

Pass: p99 improves **and** `temp_c` max stays under whatever the throttle point
turns out to be. This is the one proposal that can make things worse by
throttling, so run it for a full 10 minutes, not 60 seconds.

### 4. The compositor's presentation path is unconfigured

*Moot: there is no compositor. Every program takes the panel through KMS, and
RetroArch presents each frame once, timed to its vblank. Kept for the
reasoning, which is why the presentation path was worth suspecting.*

The sway config sets no output mode, no `max_render_time`, and no adaptive
sync, on a 1280x960 120 Hz panel. `sway.sh` exports
`WLR_NO_HARDWARE_CURSORS=1`, and a software cursor can stop wlroots handing a
fullscreen surface straight to the display controller.

Three separate things to try, one at a time:

    swaymsg output '*' max_render_time 2      # render just before vblank
    swaymsg output '*' mode 1280x960@60Hz     # stop 120 Hz beating against 60
    # and a build with WLR_NO_HARDWARE_CURSORS unset, to allow direct scanout

Pass: p99 drops. This one is a real candidate for the flycast variance, because
`top -H` showed nothing saturated, which means blocking, and presentation is
the other thing an emulator blocks on besides audio.

### 5. Every interrupt lands on the little cluster

`irqaffinity=0-2` is a boot argument and a deliberate one, but it puts GPU,
display and audio interrupts on the slowest cores, which under schedutil sit
at 556800 kHz until something wakes them.

    grep -E "kgsl|msm_drm|lpass|q6" /proc/interrupts
    echo 8 > /proc/irq/<n>/smp_affinity      # a big core

Pass: p99 drops. Measure before deciding, since moving interrupts onto the
cores running emulation can also hurt.

### 6. Idle exit latency

`cpuidle.governor=teo` with deep states costs wakeup latency on a workload that
sleeps and wakes every frame. BUGS.md already carries an open `096-cpuidle`
entry.

    for s in /sys/devices/system/cpu/cpu*/cpuidle/state3; do echo 1 > $s/disable; done

Pass: p99 drops. Revert afterwards regardless: this costs idle power and is
only worth keeping if it is wired to gameplay.

## Part 2: flycast and the audio stack

The symptom is reduced framerate, large frametime variance and audio
artefacts together. What is already known:

* Nothing is saturated. `top -H` during a drop: Flycast-emu 42.6% of one core,
  Flycast-rend 14.5%, SDLAudioP0 2.3%, 87.8% of the machine idle at load 1.14.
  **So flycast is waiting, not working.**
* The GPU clock is not it. `performance` pins 680 MHz and the drops continue.
* The audio backend is not it by itself. `sdl2` replaced `pulse` and the
  stutter survived.
* Frametimes were quantised: 22ms and 120ms, which are one and about six of the
  21.3ms graph quantum. That is an emulator gated on the audio buffer.

### The experiment that settles it

Flycast gates emulation on the audio buffer, so if audio is the gate, frametime
p99 should track the quantum. Sweep it without rebuilding anything:

    for q in 1024 512 256 128; do
      pw-metadata -n settings 0 clock.force-quantum $q
      perf-probe quantum-$q 60      # play through the same section each time
    done
    pw-metadata -n settings 0 clock.force-quantum 0

**If p99 falls with the quantum**, audio gating is confirmed, the fix is to go
as low as stays stable, and the xrun column tells you where that is.

**If p99 is flat across all four**, audio is not the gate. Stop working on the
audio stack for this symptom and go to Part 1 item 4: presentation is then the
remaining thing flycast can block on.

This has never been run, and it decides which half of the work is worth doing.

### Changes already queued

* **Quantum 256.** The device is running 512 because the agreed 256 was
  orphaned on a merged branch. #95 lands it. Test it at runtime first, since
  `pw-metadata` makes the build unnecessary for a verdict.
* **Native 44.1 kHz.** #96, three patches. Removes the adaptive resampler and
  its reconvergence after every xrun. Worth more at a small quantum than a
  large one: 84us of work is 0.4% of 21.3ms but 1.6% of 5.33ms.

### If audio is the gate

* Sweep `backend = alsa` against `sdl2`. Different buffering path, one run
  each, no rebuild: edit `/storage/.config/flycast/emu.cfg` **and**
  `/usr/bin/start_flycast.sh`, which rewrites it on every launch.
* Check what flycast asks for. `pw-top`'s QUANT column on flycast's own node
  against the sink's says whether it is following the graph or asking for
  something of its own.

### If presentation is the gate

* `rend.vsync` is written from the `vsync` emulationstation setting and
  defaults to off. Off means flycast presents as fast as it can and the
  compositor decides, which is a worse place for the decision to live. Test
  both.
* `pvr.rend` is 4, Vulkan. Try 0, OpenGL. If the variance follows one renderer,
  it is the driver path, and that is the same turnip Dolphin freezes on.

## Recording results

Keep the `/storage/perf/<label>/` directories. Two runs are only comparable if
`env.txt` differs in exactly the thing being tested, which is the whole reason
it is written.
