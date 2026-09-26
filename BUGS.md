# Known bugs and loose ends

Things found and not fixed. GitHub issues are the tracker for work with a
shape; this file is the record of everything else, including findings too
small, too uncertain or too far from a fix to file. Nothing here is
speculative: each item is something observed on the device or read in the
tree, with enough detail to pick up cold.

Add to it when you leave something behind. When something is fixed, move it to
Resolved at the bottom rather than deleting it: what was wrong and why is worth
keeping, especially where the first few explanations were wrong.

## Landed on 26 September, not yet run on the device

Each has its check; do them before building on top.

* **Charger current limit, kernel patch `0510` (#354).**
  `/sys/class/power_supply/battery/constant_charge_current_max` should read
  the firmware's ceiling in µA, and while charging `echo 2000000 >
  .../constant_charge_current` should bring `current_now` to about 2 A. An
  error on the write means the firmware rejects the property and charging is
  unaffected. The protocol was read from Qualcomm's downstream
  `qti_battery_charger.c`, not from a device.
* **`charge-throttle` (#355)**, the service that steps the current at 40, 42
  and 44 °C of battery temperature. `journalctl -u charge-throttle -f` while
  charging and playing: a line such as `battery 402: charge current 3000000
  uA` when the battery crosses 40 °C, and `current_now` following it. `no
  charge current limit on this kernel` means the patch above is not working.
* **RetroArch's automatic output rate (#356)**, `audio_out_rate = "0"`. The
  log carries `[Audio] Output rate picked for the core's … Hz: … Hz` at
  every audio init. On an N64 game the second such line, after the game
  programs its DAC, should name 32000 or 44100, and `hw_params` should show
  the same rate. A regression here would sound like every game at once, so
  a session across systems is the test.
* **strace 7.2 (#357).** The SHA-256 in the recipe came from the GitHub
  release asset because strace.io was unreachable from the sandbox. A hash
  mismatch at unpack is that, and the fix is the checksum of the tarball
  strace.io serves.
* **Game guides through RetroArch (sdl2text)** worked on the device on the
  evening of 26 September: M2 opens the guide, the D-pad scrolls and zooms,
  M2 returns to the game where it was. So sdl2text does get DRM master, the
  udev button for M2 is 16, and the held-paddle grace holds. Still open:
  whether a Vulkan core (parallel-n64, Flycast) comes back cleanly from the
  context destroy and reset the handover forces, and whether it stutters
  for a moment afterwards while it refills its pipeline and texture caches.
* **Settings > Consoles, latency (preemptive frames, 1).** Not yet run on
  the device. With `snes.profile=latency` in system.cfg, a SNES game's
  RetroArch config should carry `preemptive_frames_enable = "true"`,
  `run_ahead_frames = "1"` and `video_scale_integer = "false"`, the shader
  stays, and the statistics overlay's
  core time should rise only a little while nothing is pressed. A
  `[Run-Ahead Preemptive]` warning in the log means the core does not
  support it and it goes on the NO_RUNAHEAD list; a frame flickering back
  on a press means its savestate is not deterministic, same list.
* **Which N64 games run at 32 kHz.** Super Mario 64 and the two Zeldas are
  believed to; RetroArch's statistics overlay, or the `Sink rate` log line,
  says. Nothing depends on the list any more, it is only worth knowing.

## Unexplained

### Suspend power draw

Tracked in [#62](https://github.com/portare-ch/portareos/issues/62). The
device loses meaningful charge overnight and the cause is not known.

Three hypotheses were tested on hardware and all three were wrong:

* `apss` in `/sys/kernel/debug/qcom_stats/` reaching sleep was read as the SoC
  reaching sleep. It is the apps subsystem only.
* Interconnect `avg` votes were read as the DDR floor. Setting `ebi` to zero
  changed nothing.
* CPU frequency was read as what drives DDR. Moving the governor moved the
  clocks and DDR did not follow.

What is established: DDR has not touched its 200 MHz minimum since boot, in
any state, and with the frontend stopped it pins at 3187 MHz on an idle
system. `aosd`, `cxsd` and `ddr` in `qcom_stats` all read `Count: 0`, though
several files in that directory are empty on this SoC so the zeros may mean
"not reported" rather than "never entered".

Nobody has measured `/sys/class/power_supply/*/current_now`. Everything so far
has been proxies. Start there.

### CX never leaves performance state 64

`pm_genpd_summary` shows `cx on 64` with three holders: `898000.serial`
(uart14, the gamepad MCU by the `serial1` alias), `pcie_0_gdsc` at 64
(ath12k), and `mmcx` at 64 (display controller). Whether any of them releases
during suspend is unknown.

### 096-cpuidle

```sh
# Disable cpu0 idle state 1, seems to cause GMU issues
echo 1 > /sys/devices/system/cpu/cpu0/cpuidle/state1/disable
```

Inherited from ROCKNIX with no more explanation than that comment. We now know
the GMU does misbehave on this platform, so the workaround may be covering
something real. Nobody has established what, or whether the quirk still earns
its cost: `irqaffinity=0-2` sends every interrupt to the cluster it cripples.

### pcie_ports=compat

On the kernel cmdline, which disables the PCIe port services including PME.
`CONFIG_PCIEASPM_DEFAULT=y` leaves link power states at whatever firmware set,
and Qualcomm firmware commonly leaves ASPM off. Never investigated. Costs
power awake as well as asleep if the ath12k link never reaches L1SS.

## Patches applying with fuzz

`scripts/unpack` runs `patch -p1`, which takes GNU patch's default fuzz factor
of 2. A hunk can apply with two lines of context discarded and the build says
nothing. Re-measured on 26 September against a clean 7.2.5 tree, applying the
97 kernel patches in the build's order: **20 apply with fuzz, none fail.**

`0002` input-polldev, `0005` btrtl RTL8733BU, `0033` HTR3212 leds, `0054`
goodix, `0055` `0056` `0057`x2 `0104` `0105` panels, `0058` Odin2 Mini
backlight, `0059` hynitron, `0121` rpmhpd gmu rails, `0210` sdhci-msm,
`0501` wifi/bt mac, `0504` compat input syscalls, `1003` rsinput ff, `1007`
ufs hibern8, `1048` PCI suspend opp, and the qce runtime-pm patch.

Most are for hardware this fork does not build and could go. Ours among them:
`0105` the Nova panel, `0210` microSD SDR104, `1003` gamepad force feedback,
`1007`, `1048` and `0501`.

`1051` is not in the list: GNU `patch` takes it cleanly. `git apply` reports
`corrupt patch at line 32` because its final context line is bare rather than
a single space; the build does not use `git apply`.

A trap for whoever measures this next: `patch -s` silences the "succeeded
with fuzz" lines along with everything else, and a run with it reports zero.
The first count on 26 September was taken that way and was wrong.

Making the build reject fuzz outright (`patch -F0`) would need all twenty
regenerated first.

## Dolphin

Both findings below were made on the standalone Dolphin. The image now runs
Dolphin as its libretro core inside RetroArch, and neither has been re-tested
there. They stay until someone does.

### Soul Calibur II freezes

Diagnosed but unconfirmed. `Dolphin.ini` ran Dual Core with
`SyncOnSkipIdle = False` and `SyncGPU = False`, which is the exact combination
`CommandProcessor::HandleUnknownOpcode` singles out as making an unknown FIFO
opcode "very likely". `SyncOnSkipIdle` is restored to upstream's default.

It still freezes, so that was not it, or not all of it. Dolphin's own
escalation from here is `SyncGPU = True`, then `CPUThread = False`. One at a
time. `/var/log/exec.log` now carries the reason, since the patch that silenced
20 PanicAlerts is gone.

What the kernel rules out: a 2.5 hour dmesg covering a play session has no GPU
fault, no `*ERROR*` from msm, no hung task, no rcu stall, no OOM. One
`dpu_encoder_resource_control: invalid parameters` from the display controller,
once, and nothing else. So whatever stops is stopping in userspace, without the
kernel noticing. That is Dolphin's own threads or the Vulkan driver deadlocking
before it submits anything the kernel would object to, and it argues against
the GPU firmware being the cause.

The measurement nobody has taken: while it is frozen, dump per-thread state.

    P=$(pidof dolphin-emu-nogui)
    for t in /proc/$P/task/*; do
      echo "$(basename $t) $(cut -d' ' -f3 $t/stat) $(cat $t/wchan) $(cut -d' ' -f1 $t/syscall)"
    done

That separates the three candidates in one shot. Threads blocked in an ioctl on
a DRM fd means the driver. Everything in a futex wait means a deadlock between
Dolphin's own threads. A thread in state R with no syscall means the JIT is
spinning.

Soul Calibur III is not a way around this: it is PS2 only, so it belongs to
armsx2, which is reported to run fine.

### Truncations in the 240p patch

`004-enable-240p-res.patch` assigns `GetEFBScalef()` to an `unsigned int` in
`TryToSnapToXFBSize` and to an `int` in `GetCustomCrop`, both in `Present.cpp`.
At the 240p setting a scale of 0.5 truncates to 0. Neither crashes and both
affect only that one resolution. Left alone because picking a rounding is a
design call, not a fix.

## Flycast

Found on the standalone Flycast, with its own audio backend, `emu.cfg` and
`start_flycast.sh`. The image now runs Flycast as its libretro core, where
RetroArch owns audio, vsync and pacing, so most of the reasoning below is
about a program that is no longer shipped. Whether Tony Hawk still stutters
under the core is the one thing worth checking; if it does not, this moves to
Resolved as "gone with the standalone".

### Tony Hawk's Pro Skater stutters

The audio backend was changed from `pulse` to `sdl2` when pulseaudio was
removed, on the theory that the backend was behind the stutter. It still
stutters, so it was not.

The change did reach the device: `start_flycast.sh` rewrites `backend =` in an
existing `/storage/.config/flycast/emu.cfg` on every launch, so a config
predating the switch is not the explanation.

Nor is staleness. `PKG_VERSION` is `5aa091f`, which is exactly `v2.7`, the
newest tag upstream has.

Measured. The counter sits at 30, dips to 26 when the audio stutters, and
falls as far as 9 at its worst. So this is not presentation: frames are not
being made. Whatever is wrong is upstream of the compositor.

Ruled out since, in order:

The audio backend. `sdl2` replaced `pulse` when pulseaudio was removed and the
stutter survived it.

The GPU clock. Utilisation looked damning at first: 10 to 20 percent at full
speed, 80 to 90 while dropping. But pinning the devfreq governor to
`performance` holds the GPU at its 680 MHz ceiling and the drops continue
essentially unchanged. (That test did expose a real bug, a suspend hook
latching the GPU to powersave, but a different one.)

CPU shortage. `top -H` during a drop: `Flycast-emu` at 42.6 percent of one
core, `Flycast-rend` at 14.5, `SDLAudioP0` at 2.3, and 87.8 percent of the
machine idle with a load average of 1.14. Nothing is saturated. There is no
shortage of anything.

So flycast is waiting, not working. Which puts the audio path back in front,
for a better reason than the first guess: flycast gates emulation on the audio
buffer, so a backend that delivers late does not follow a frame drop, it causes
one. The `SDLAudioP0` thread exists and is nearly idle, which is what a thread
blocked on a slow consumer looks like.

The next measurement is `pw-top` during a drop, watching flycast's node for a
climbing ERR count and for what quantum it negotiated. `backend = alsa` against
`sdl2` is the A/B underneath it.

That `pw-top` was taken, during Tony Hawk gameplay on a KMS launch:

    R  50  1024  44100  18.9us  53.1us  0.00  0.00  0  S16LE 2 44100  alsa_output...Speaker__sink
    R  47  1024  44100  27.2us  17.2us  0.00  0.00  0  S16LE 2 44100  Audio Stream

Quantum 1024 at 44100, ERR 0 on both flycast's stream and the sink, wait and
busy times in the tens of microseconds. No xruns, and the rate is the one the
Dreamcast wants, so the audio path is not visibly late at the moment the
frames are missing. That weakens the gating theory rather than settling it:
the remaining A/B, `backend = alsa` against `sdl2`, is still untried.

The baseline is 30 because the game renders at 30. Flycast says so itself:

    N[RENDERER]: Swap interval changed to 4

which is `swapInterval` 2, from DupeFrames on a 120 Hz panel, times
`gameSwapInterval` 2. `setSwapInterval` is called with what the game asks
for, and Tony Hawk asks for every second Dreamcast vblank. So the 30 is not
evidence of anything being starved, and the earlier reading of it as "half
rate is what an emulator gated on audio does" should not be carried forward.

Per-thread sampling during gameplay, which refines the earlier `top -H`
numbers: `Flycast-emu` 17 percent of one core, `Flycast-rend` 3 percent, GPU
load 4 to 14 percent with the devfreq governor pinned to `performance` and
the clock held at 680 MHz. Still waiting, not working.

One more thing the frametime logs show. With vsync on, gameplay frametimes
land on multiples of the 8.33 ms vblank - 599 frames at 33 ms, 309 at 41, 207
at 50 - so a frame that misses by a hair costs a whole vblank and 30 fps
becomes 24, then 20. Flycast's Vulkan backend always takes FIFO on ARM, and
until SDL2 was replaced by sdl2-compat nothing in the image could tear under
sway either. `rend.vsync = no` now ships as the default and removes the 24
fps step, but the drops themselves survive it, so this was never the cause.

Note that `pvr.AutoSkipFrame` is not it unless the ES `auto_frame_skip` setting
has been set by hand. Nothing in the tree defines a default for it, so
`get_setting` comes back empty and the launcher takes the `else` arm, which
writes 0.

## Audio

### hdmi_sense sink match is unverified

The external display is DisplayPort over USB-C alt mode, so the connector is
`DP-1`. The script scans DP connectors and matches sinks on `hdmi`,
`displayport` and `dp`, on the assumption that the ALSA device behind a DP
output is still named for HDMI on this SoC. Its header comment still points
at `111-sway-init`, which no longer exists. **Nobody has docked the device and
run `wpctl status` to check.** If the sink matches none of those, the regex
needs another alternative.

### Two pactl calls dropped rather than ported

* `set-default-source <sink>.monitor` has no PipeWire equivalent: a monitor is
  a port on the sink node, not a node, so there is no id to make default.
  `pipewire-pulse` synthesises those sources for pulse clients only. This is a
  real behaviour change and nobody has said whether it mattered.
* `set-card-profile` was already dead. `DEVICE_PIPEWIRE_PROFILE` is exported in
  `quirks/profile.d/999-export` and never assigned.

### Names that lie

`hdmi_sense`, its udev rule `99-hdmi.rules` and its status file
`/run/hdmi-status.last` are all named for hardware this device does not have.

## Display and power

### /usr/bin/external-display is not in the tree

`power-handler` calls it when it exists and otherwise answers "no external
display" and blanks through the front-end. The helper is referenced in
comments as the thing that blanks internal panels only, and it has never
existed here. Either write it or finish removing the indirection.

### The DPMS toggle is gone

`system.suspend.dpms` chose between a real DPMS off and dropping the backlight.
Its only reader was `portareos-fake-suspend`, removed in `a61c3f72a4`, and the
setting went with it. The blank path now always does a real DPMS off, through
the front-end since sway went, which is the better default, but the choice no
longer exists.

### The power LED does not exist

`sleep.d/pre/000-led`, `sleep.d/post/099-led-restore` and `power-handler` all
write to `/sys/class/leds/power-led`. That node is declared only in the AYN and
AYANEO device trees, so every `[ -d "${POWER_LED}" ]` guard is false here and
the writes never happen. Dead, not harmful. The analogue stick LEDs are real
and that code stays.

Worth knowing: `power-handler` lights the LED at press time specifically so the
press does not feel dead while WiFi tears down. On this device that comfort
feature does nothing.

## rsinput

### Truncated frames are still dropped

`1013` fixed the batch-wide checksum that was discarding whole receive batches
and added header resynchronisation. What it does not do is buffer a partial
frame for the next callback: `rsinput_process_data()` returns when
`len < frame_length` and those bytes are lost. Proper reassembly needs
persistent state across callbacks.

## Build and process

### Changed defaults still need a migration

Half fixed. `post-update` now runs an `--ignore-existing` pass over
`/usr/config`, so a config file that is *new* in an image reaches a device
that has already booted, where before only `userconfig-setup` did that and
only once, guarded by `/storage/.configured`.

A changed *value* inside a file the install already has still cannot be
delivered that way, and needs a one-shot migration at the bottom of
`post-update`. There is a `migrate` helper and a marker directory for it now,
so each runs once and a later deliberate choice is not undone on the next
update. Two exist, for `system.cpugovernor` and `FpsLimit`.

The trap to remember: shipping a new default in a config file is not enough on
its own. Ask whether an existing device can receive it.

And the thing to know about the other direction: parts of `/usr/config` are
copied over the top on every update, not merged, so shipping a file into one
of those paths hands the image ownership of it. `retroarch.cfg` and the whole
of `retroarch/config/`, `.opt` files included, work this way on purpose.

That is a deliberate trade, not an accident to be guarded against. A core
option changed in the RetroArch menu does not survive an update for any core
the image seeds. In exchange, an updated device and a freshly flashed one are
in the same state, and a build can be tested without first working out which
of the settings on the device came from it. One copy of what was there is kept
the first time, at `config.pre-refresh`.

So the question to ask about a new default is still whether an existing device
can receive it - and for these paths the answer is now yes, by overwriting.

### Do not reuse a merged branch

Three pull requests, [#59](https://github.com/portare-ch/portareos/pull/59),
[#61](https://github.com/portare-ch/portareos/pull/61) and
[#73](https://github.com/portare-ch/portareos/pull/73), arrived as conflicts
that were really reverts: a branch whose PR had already merged, still carrying
old copies of merged work and a base predating later merges. Merging any of
them would have undone real changes.

A branch whose PR has merged is spent. Start a fresh one from the new default
branch.

### "does not close #62" closes #62

GitHub's linked-issue parser matches `close #62` and ignores the negation, so
that sentence in a pull request body closes the issue it disclaims. It happened
once, in #70, and the same phrasing sits in #68's commit message.

## Resume time

rsinput and Bluetooth are under Resolved, worth about 3.2s between them. What
is left:

* **WiFi**, was 10.6s to `associated`. The rfkill is not optional:
  `ath12k_core_continue_suspend_resume()` returns 0 and does nothing unless
  `ar->ah->state == ATH12K_HW_STATE_OFF`, and `wcn7850 hw2.0` does carry
  `.supports_suspend = true`, so the radio has to be down for the driver's
  suspend path to run at all. The reassociation cannot be avoided.

  Measured split: NetworkManager's wake is only ~1.1s, consistently, and a
  flat `sleep 4` in `wifi-resume` was better than a third of the total. That
  is now a readiness poll, and it reports `WIFI ready after 0ms`, meaning iwd
  answered on the first try and the whole four seconds was wasted. Or meaning
  the readiness test answers before the chip is up, in which case the scan
  fires too early and iwd's backoff costs a minute. Those look identical from
  that log line. **Nobody has measured resume to `associated` since**, and
  that is the one number that separates them.

  What remains beyond it is the firmware reload on unblock and the scan
  itself, roughly 5s. Association once the scan lands is 26ms, so the scan is
  the target. A directed scan on the pinned network's channel would be the
  thing to try, but `iwctl` does not expose one.

`CONFIG_PM_DEBUG` is off, so `pm_print_times` is unavailable and per-device
suspend and resume timings have to be read out of `dmesg` timestamps by hand.
Turning it on is cheap and would make this measurable.

## Resolved

Kept rather than deleted. Several of these took more than one explanation to
find, and the wrong ones are recorded too.

### 44.1 kHz on the speakers: five gates, the last two found late

The Dreamcast's AICA, the PS1 SPU and the PSP are 44.1 kHz with no 48 kHz
mode. Five things pinned the speaker path (`PRIMARY_MI2S_RX` into two
`awinic,aw88166`) to 48 kHz:

| gate | where | fix |
|---|---|---|
| backend DAI rate masks | `q6dsp-lpass-ports.c` | `1052` |
| backend hw_params fixup | `sc8280xp.c` | `1053` |
| MI2S bit clock fixed by the device tree | `sc8280xp.c` | `1054` |
| frontend PCM caps `rate_min = rate_max = 48000` | `AYN-Odin2-tplg.bin` | `extra-firmware/sources/tplg-allow-44100.py` |
| bit clock rate set but not re-voted | `sc8280xp.c` | `1054`, second version |

The fourth is why `1052`-`1054` changed nothing on their own: the topology
caps the frontend before any kernel mask is consulted, so `aplay -r 44100`
was refined to 48000 and PipeWire's allowed rates never mattered. Neither the
amps nor the DSP were ever the limit.

The fifth was measured on hardware with the topology widened by hand. A q6dsp
clock only reaches the DSP when it is prepared, and startup prepares it before
`1054` sets the rate, so each stream started on the previous stream's bit
clock and `APM_CMD_GRAPH_START` failed on every rate change. Opening the same
rate twice ran cleanly the second time, at 44100 (bit clock 1411200) as at
48000, which is what gave it away. It also made one failed 44.1 stream take
48 kHz down with it until the next rate change, which looked like a wedged DSP.

**Confirmed on hardware** on 24 September (#290): with the widened topology
loaded live and the kernel from nightly 126, Tekken 3 ran with the link at
44100 and a bit clock of 1,411,200, Super Mario World at 32000 and
1,024,000, and the link switched 48 → 32 → 48 → 44.1 kHz between games with
nothing in `dmesg`. The same gates, widened once more, are what carry 32 kHz
(#291, #297). Not recorded in that test: the headphone path
(`RX_CODEC_DMA_RX_0`) at 44.1 or 32 kHz, which `AUDIO_SAMPLE_RATES.md` covers
in theory and nobody has listened to.

### Gone with EmulationStation and sway

Three items were about the old front-end and went with it (#222,
portarelauncher replaced both). Kept in one place so a future import does
not trip over them: the repeated `Unknown element of type "notification"`
theme warning, never explained and now moot; the frontend redrawing every
loop iteration with no damage tracking, which the launcher's dumb-buffer
text rendering does not have; and `isAvailable()`, removed from
`emulationstation-sdl3` because its only caller hid the whole VOLUME group.
The `pactl` findings above stay, since the scripts they concern are still
in the image.

### The gamepad failed to resume

`rsinput_rx()` treated every serdev receive callback as exactly one frame:
checksum the whole batch, discard it all on a mismatch. serdev frames nothing,
so a batch holding two frames, a partial frame, or a frame behind power-cycle
noise was thrown away entire. At resume that was the MCU's version reply, so
the handshake added in `1012` timed out three times and gave up with
`-ETIMEDOUT`, burning 1.48s of a 2.85s kernel resume and leaving the pad on a
driver that had given up.

`rsinput_process_data()` already validated each frame separately, so the fix in
`1013` was to delete the batch-wide check and add header resynchronisation.

**Confirmed on hardware.** Across three resumes the version reply is parsed and
the parameters acknowledged 13ms later, with no `Checksum mismatch`, no timeout
and no `-110`. That the reply is parsed at all is the proof: the batch checksum
destroyed it before.

Worth remembering: `1012` was blamed first, and it was innocent. It could not
succeed while the layer beneath it was discarding the reply.

### Bluetooth reloaded its firmware on every resume

1.76s of `hmtbtfw20.tlv` and `hmtnv20.bin` on each resume, and self-inflicted.
`hci_qca` sets `HCI_QUIRK_NON_PERSISTENT_SETUP` when it controls the chip's
power, and `hci_dev_setup_sync()` then runs `hdev->setup` on *every* open, not
just the first. `sleep.sh` stopping bluetoothd is what closed the device.
`qca_pm_ops` already carries the controller through system suspend in in-band
sleep with its firmware intact, so it just had to be left alone.

**Confirmed on hardware.** `QCA Downloading` now appears only at boot, at 2.9s
and 4.0s uptime, and on none of three later resumes.

Untested: whether a paired controller still reconnects after resume. That is
the failure mode that would send this back, and restoring the two `systemctl`
calls in `sleep.sh` is the whole revert.

### EmulationStation had no volume bar and no volume control

Three separate faults wearing one symptom, which is why it took three goes.

1. **The hardware +/- keys never reached ES at all.** `ViewController::input`
   maps volume to `joystick2up`, the right stick. `input_sense` owns the
   physical keys and calls `/usr/bin/volume`.
2. **`/usr/bin/volume` was broken by the pulse ban.** It ended in `pactl
   set-sink-volume`, and #54 deleted `pactl`. Fixed in #63 by moving to
   `wpctl`, with the cubic curve converted explicitly since `wpctl` takes a
   linear factor where `pactl` took a percentage.
3. **ES could not reach PipeWire.** `PipeWireControl` was a file-scope static,
   so its constructor ran before `main()` and before the log existed: every
   error went nowhere and a single failed connect was permanent. Fixed in
   `emulationstation-sdl3#12` by constructing on first use and retrying.

**Confirmed on hardware.** The overlay now appears on a hardware volume press,
which exercises the entire chain in one go: `input_sense` to `/usr/bin/volume`
to `wpctl` setting the sink, `node_param` seeing `channelVolumes` change on the
PipeWire loop thread, and `VolumeInfoComponent` noticing the new value 40ms
later.

A wrong turn worth recording: the missing overlay was blamed on the
`Unknown element of type "notification"` theme warnings. It was not them, and
they are still there.

### dwc3 never runtime suspended

`a600000.usb` held `avg 1000000  peak 2500000` on the path to `ebi`
permanently, awake, on battery, with nothing plugged in. Those are
`USB_MEMORY_AVG_SS_BW` and `USB_MEMORY_PEAK_SS_BW` from `dwc3-qcom.c` to the
digit. `dwc3_core_probe()` ends with `pm_runtime_forbid()` and the only
`pm_runtime_allow()` calls are on error and teardown paths, so `power/control`
stayed `on` and `dwc3_qcom_runtime_suspend()`, which is what calls
`dwc3_qcom_interconnect_disable()`, could never run.

**Confirmed on hardware.** Writing `auto` took `runtime_status` to `suspended`,
the usb row to `0 0`, and the `ebi` aggregate from 1735805 to 735805. Shipped
as a udev rule in #70.

This is an awake-power fix. The system suspend path drops the vote by itself
through `dwc3_qcom_pm_suspend()`, so it does not touch the suspend draw.

### Blanking the panel did not blank anything

`power-handler` called `external_display blank`, and
`/usr/bin/external-display` is not in this tree, so the call returned 1 and
nothing happened. The flag was set, the backlight went dark on a separate path,
and the DPU carried on scanning out at 120Hz behind it.

**Confirmed on hardware.** `swaymsg "output * power off"` takes
`ae00000.display-subsystem` from `avg 735805` to `0` and the whole `ebi`
aggregate with it. A sway fallback is in place, internal outputs only.

### ondemand parked the little cluster at maximum

`008-perfmode` preferred `ondemand` wherever it existed. **Measured**: policy0
at 2016000 kHz on a 97% idle system, dropping to 556800 under `schedutil`. That
is also the cluster `irqaffinity=0-2` sends every interrupt to.

It did not move DDR, which was the hypothesis it was meant to test, but it
stands on its own.
