# Debug tools guide

Use these tools to capture a failure, compare game runs, or measure the Nova's
display, audio and power behavior. Start with the tool for the symptom rather
than changing several settings at once.

[Feature overview](FEATURE_OVERVIEW.md#debugging-and-measurement) ·
[Device test plan](TEST_PLAN.md) · [Known issues](../BUGS.md)

## Where the tools run

**Nova commands** below run in a root SSH session. Find the IP address and
generated root password under **Settings > About**, and enable SSH in Settings.
In host examples, replace `nova` with that address or your SSH host alias.

**Host commands** run from this repository's root on your computer. They need
SSH/SCP; `display-check` also needs Python 3. Use a unique run name each time:
the recording tools reuse or overwrite files with the same name.

The [debug package](../packages/virtual/debug/package.mk) installs the eight
tools in the first group below. Unofficial builds include it by default;
official builds, including official nightlies, omit it by default.
`DEBUG_PACKAGES=yes` overrides that choice. For a local image build:

```sh
DEBUG_PACKAGES=yes make docker-SM8550
```

The installed tools and debug symbols are separate choices: merely including
gdb does not provide source-level symbols for every emulator or library.

| Tool | Runs on | What it answers |
| --- | --- | --- |
| `gdb` | Nova, debug package | Where are the program's threads stopped? |
| `strace` | Nova, debug package | Which system calls block or fail? |
| `vblank-rate` | Nova, debug package | What is the panel's actual refresh rate? |
| `vrr-probe` | Nova, debug package | Does the panel follow changed modes and variable frame schedules? |
| `present-probe` | Nova, debug package | What does Vulkan presentation do with a known schedule? |
| `tear-test` | Nova, debug package | Does the display controller scan out mixed frames? |
| `pcm-flags` | Nova, debug package | What audio capabilities and period sizes does the driver advertise? |
| `pcm-floor` | Nova, debug package | Which audio periods sustain playback without underruns? |
| `perf-probe` | Nova, ordinary image | What clocks, temperature, charge and frame times accompanied a game run? |
| `idle-probe` | Nova, ordinary image | What consumes power and wakes threads while idle? |
| `coremap-check` | Nova, ordinary image | Do PS2 threads and background services use their assigned CPUs? |
| PortScope | Nova, launcher | What do the buttons, sticks, triggers and report stream actually produce? |
| MangoHud | Nova, optional game overlay | What are the performance statistics and frame intervals? |
| `tools/display-trace` | Host, controls Nova | Can I capture display events and retrieve the run? |
| `tools/display-check` | Host, reads saved files | Do presentation records and pixels agree with the kernel trace? |
| `tools/device-tests` | Host, inspects Nova | Which automatic device configuration checks pass, fail or skip? |

## First capture the context

On the Nova, create a directory for the report and collect the build and logs:

```sh
mkdir -p /storage/debug-report
cat /etc/os-release > /storage/debug-report/os-release.txt
uname -a > /storage/debug-report/kernel.txt
systemctl --failed > /storage/debug-report/failed-services.txt
journalctl -b --no-pager > /storage/debug-report/journal.txt
dmesg > /storage/debug-report/dmesg.txt
```

Record the game, scene or save, settings changed, charging state and whether
VRR was enabled. Capture a baseline and then repeat the same scene with one
change. Debuggers and tracers themselves affect timing; collect latency
measurements separately from gdb or strace sessions.

## Program failures: gdb and strace

### gdb: thread backtraces

With a stuck RetroArch game still running, on the Nova:

```sh
game_pid=$(pgrep -xo retroarch)
test -n "$game_pid" && gdb -q -batch -p "$game_pid" \
  -ex 'set pagination off' -ex 'thread apply all bt' -ex detach \
  > /storage/debug-report/backtrace.txt 2>&1
```

Attaching pauses the process while the backtraces are taken; `detach` resumes
it. Use the matching executable and libraries with symbols for useful function
names and source lines. A backtrace from another build can be misleading.
Change the process name to investigate a different program.

### strace: system calls

On the Nova, attach to RetroArch and reproduce the problem:

```sh
game_pid=$(pgrep -xo retroarch)
test -n "$game_pid" && strace -f -tt -T -p "$game_pid" \
  -o /storage/debug-report/strace.txt
```

Press Ctrl+C to stop tracing and detach. `-f` includes threads and child
processes, `-tt` adds timestamps, and `-T` records syscall duration. Look for
repeated errors or long waits around the failure; an idle thread waiting in
`futex` or `poll` is not by itself a bug.

## Game performance, CPU placement and controls

### MangoHud: on-screen statistics and frame logs

On the Nova, enable the overlay before launching the game:

```sh
. /etc/profile
set_setting portareos.mangohud.enabled 1
```

Relaunch the game; L1 + Y shows or hides the overlay. To record a run, create
`/storage/mangologs` and set these options in
`/storage/.config/MangoHud/MangoHud.conf` before launching:

```ini
output_folder=/storage/mangologs
autostart_log=1
log_duration=60
log_interval=0
```

These settings start a 60-second per-frame log after one second. Remove the
automatic logging options afterward. `application_interval_ms` measures the
spacing between presents; `display_interval_ms` measures when frames reach
the display, when timing records are available. Blank display intervals mean
no record was available, not a zero-duration frame. Keep the per-frame CSV,
not just its `_summary.csv` companion.

### perf-probe: comparable game runs

With the game and its MangoHud recording running, on the Nova:

```sh
perf-probe baseline 60
cat /storage/perf/baseline/summary.txt
```

The default duration is 60 seconds. Each label creates a directory containing
`env.txt`, `samples.csv`, `summary.txt` and, when found, `frametimes.csv`.
Settings are recorded once, machine statistics roughly once a second.
Frame-time summaries distinguish application and display intervals.

The probe copies the newest non-summary CSV from `/storage/mangologs`; confirm
that it belongs to this run. It does not start MangoHud logging. Without gawk,
some percentile summaries are unavailable; retain the raw CSV. See the
[performance notes](../docs/performance-plan.md) for comparison procedures.

### coremap-check: PS2 thread layout

While a PS2 game is running, on the Nova:

```sh
coremap-check 5
```

It samples threads for five seconds, prints their allowed and observed CPUs,
then checks EE (`CPU Thread`) on core 7, MTVU on 3 and GS on 4. It also checks
the game's cgroup and system CPU isolation. Exit status is 0 for PASS, 1 for
FAIL and 2 when no supported emulator is running. Currently the documented
layout in this tool is ARMSX2 only.

### PortScope: input diagnostics

Open **Settings > Diagnostics** on the Nova. Exercise every button, stick and
trigger and inspect the report rate. Hold **SELECT** to inspect the raw MCU
and gpio-keys path before InputPlumber; InputPlumber is temporarily stopped
for that view. Use **Home + Start** to exit. This separates a hardware/driver
input problem from one introduced by input translation.

## Idle power: idle-probe

Exit games and players, unplug the charger, then run on the Nova:

```sh
idle-probe 60 > /storage/debug-report/idle.txt
```

Leave the device alone and keep the screen state consistent between runs.
The default duration is 300 seconds. Output includes mean battery power,
interrupt and context-switch rates, deep-idle entries on cores 0–2, and the
most active threads. The tool refuses to run while charging or while a
RetroArch game is detected. Its thread activity is derived from context
switches, not a direct count of hardware wakeups.

This measures awake idle, including a blanked screen; it does not measure
suspend current. See [power measurements](POWER.md) for the suspend procedure.

## Display timing

### vblank-rate: measure the running display

This tool can run alongside a game or the launcher; it does not need to own
the display. Keep the panel awake for the entire measurement. On the Nova:

```sh
vblank-rate --seconds 30
vblank-rate --seconds 10 --intervals
```

For a known fixed mode, add its expected rate, for example
`--rate 119.652 --target 119.652`. `--rate` only estimates how many vblanks
to wait for; it does not change the display mode. `--target` reports error
in parts per million. Use the `CLOCK_MONOTONIC_RAW` result for mode accuracy:
the other clock can be slewed by time synchronization. Under VRR the measured
rate follows the active workload. `EINVAL` commonly means the panel is blanked.

### Exclusive display tests

`tear-test`, `vrr-probe` and `present-probe` take over the built-in display.
Exit games and media players first, disconnect external displays, and run
them over SSH. The examples below stop the launcher and arrange to restart
it when the subshell exits. If a session is interrupted and the menu does
not return, run `systemctl start portarelauncher` from a new SSH session.

### tear-test: validate tearing detection

First force a tear, then run the synchronized test, on the Nova:

```sh
(
  trap 'systemctl start portarelauncher' EXIT
  systemctl stop portarelauncher || exit
  tear-test --frames 1200 --tear-live
  tear-test --frames 1200
)
```

The first run repaints a visible buffer mid-scanout. It must report frames
matching neither reference CRC; if it cannot detect those deliberate tears,
a clean second run proves nothing. A synchronized run should match frame A
or B. Sequence gaps mean the CRC reader missed samples, not necessarily that
the game dropped frames. CRCs describe the display controller's output;
they cannot rule out a fault later in the link or panel.

`--rate HZ` selects a listed mode, `--stripes N` changes the pattern, and
`--card N` selects the DRM card. Without `--rate`, the implementation selects
the preferred mode. `--async` requests asynchronous flips, but a driver may
reject them; `--tear-live` does not depend on that support. Exit 1 indicates
torn frames or an error, 2 invalid arguments and 3 rejected async flips.
The deliberate-tear run is expected to return 1; do not chain it to the
clean run with `&&`.

### vrr-probe: panel modes and variable schedules

On the Nova, run eight dynamic patterns for six seconds each:

```sh
(
  trap 'vrr-probe /dev/null 1 reset; systemctl start portarelauncher' EXIT
  systemctl stop portarelauncher || exit
  vrr-probe /storage/vrr-dynamic.csv 6 dynamic vrr
)
```

The positional arguments are output CSV, seconds **per phase**, phase group
and optional `vrr`. `dynamic` uses fixed and varying frame intervals, repeated
game frames and deliberately late frames. Watch the dark patches for flicker.
`static` stretches fixed modes; `all` runs static and dynamic phases; `idle`
commits once and waits; `reset` restores the base mode and clears VRR.
`fast` tests 121/122 Hz modes beyond the normal range and is a panel experiment.
`vrr-on` and `vrr-off` only change the VRR property and deliberately leave it
set for the next client.

The CSV contains `phase,kind,t_ns`: `S` is scheduled, `C` committed, `F` the
kernel vblank timestamp, `f` when userspace read the completion, and `M/m`
the start/end of a mode set. Do not substitute callback arrival times for
scanout times. See [variable refresh](VARIABLE_REFRESH.md) for the measured
patterns and the idle-floor test. This tool has no `--help` parser.

### present-probe: known Vulkan schedules

On the Nova, exercise a fixed cadence of two, two and four refreshes:

```sh
(
  trap 'systemctl start portarelauncher' EXIT
  systemctl stop portarelauncher || exit
  MESA_VK_WSI_DISPLAY_VRR=0 present-probe /storage/present-cadence 30 observe cadence:2,2,4
)
```

The first argument is a file prefix: this writes `.presents.csv` and
`.records.csv`. The former records submitted frames, targets and deliberate
lateness; the latter records returned presentation timings. Times are
`CLOCK_MONOTONIC` nanoseconds. Each frame draws a changing barcode for CRC tests.

| Argument | Purpose |
| --- | --- |
| `observe` | Tag each present with a target and ID, then read timing records. |
| `partial` | Like observe, but leave every tenth present untagged. |
| `own` | Pace by vblank events without requesting display-timing records; requires a cadence. |
| `cadence:2,2,4` | Hold successive frames for the listed refresh counts. |
| `rate:59.826` | Target a content rate; use `MESA_VK_WSI_DISPLAY_VRR=1` for VRR tests. |
| `rate:30,60` | Step through content rates in one session, `switch=S` seconds each (default 5). |
| `read=N`, `read=count`, `read=none` | Change how timing records are retrieved. |
| `late=600:4` | Every 600th frame arrives 4 ms after its target in rate mode; cadence mode adds one refresh. |
| `mode=119.652` | Select the nearest display mode; default is the fastest. |
| `recreate=10` | Recreate the swapchain every ten seconds. |

Running with no arguments prints usage and exits 2. A completed probe alone
does not establish correct scanout; pair it with the trace/check workflow.

## Record and check display runs from the host

`tools/display-trace` runs a command on the Nova, records kernel display
events plus Mesa commit markers, and copies `NAME.*` to the host's current
directory. It stops/restarts the launcher and terminates the test command
at the end. Exit games and players first; the script kills leftover mpv
processes. It also replaces the selected run's previous device files and
changes the active tracing configuration, so run it separately from other
ftrace sessions.

From the repository root on the host:

```sh
tools/display-trace root@nova cadence-test 30 --crc -- \
  env MESA_VK_WSI_DISPLAY_VRR=0 \
  sh -c 'exec present-probe "$RUN" 40 observe cadence:2,2,4'
python3 tools/display-check cadence-test --cadence 2,2,4
```

`--no-hold`, after `--crc`, skips `vblank-rate`, which otherwise keeps the
vblank interrupt on for the run; without it, refreshes are traced only while
the client waits on a vblank, as in a game.

The probe duration exceeds the capture window so it remains active until the
wrapper stops it. Keep `$RUN` single-quoted on the host: the wrapper supplies
that prefix on the Nova. Use a capture window longer than two seconds.

For integer-multiple VRR with deliberate late frames:

```sh
tools/display-trace root@nova vrr-test 60 --crc -- \
  env MESA_VK_WSI_DISPLAY_VRR=1 \
  sh -c 'exec present-probe "$RUN" 70 observe rate:59.826 late=600:4'
python3 tools/display-check vrr-test --rate 59.826 --floor-hz 80
```

The files are `.trace` (kernel events and Mesa markers), `.out` (command
output), `.presents.csv`, `.records.csv`, and `.crc` when requested.
An optional matching MangoHud per-frame log named `NAME.mh.csv` is checked
against the same trace. The checker requires the `.trace` file, not the
`vrr-probe` CSV. `--crc` comparisons assume every new frame changes pixels,
as present-probe's barcode does; identical frames in a real game need a
different interpretation.

Read the count of untraced vblanks and unmatched events before trusting the
result. PASS/FAIL lines cover repeat buffers, cadence or rate, available
presentation records, MangoHud data and CRCs. Optional data that is absent
cannot be checked. Exit status is 1 when checks fail or no frames are found;
0 means the checks that ran passed. `--floor-hz 90` is for older 90 Hz-floor
captures; `--refresh-ms` sets the shortest refresh when the base mode differs.

If capture aborts before cleanup, stop the remaining probe, disable the three
events it enabled and restart the launcher on the Nova before another measurement:

```sh
pkill -TERM -x present-probe
echo 0 > /sys/kernel/tracing/tracing_on
for event in drm/drm_vblank_event dpu/dpu_crtc_complete_flip dpu/dpu_plane_set_scanout; do
  echo 0 > "/sys/kernel/tracing/events/$event/enable"
done
systemctl start portarelauncher
```

## Audio-driver measurements

### pcm-flags: advertised capabilities

On the Nova, query the unused second playback PCM while PipeWire holds the
first:

```sh
pcm-flags hw:0,1 32000
pcm-flags hw:0,1 44100
pcm-flags hw:0,1 48000
```

The arguments are device and sample rate; defaults are `hw:0,1` and 32000.
Output includes `BATCH`, period/buffer ranges and accepted period sizes in
frames. In the tuned shared-memory path, `BATCH` should be `no`; that flag
affects PipeWire's additional buffering. Divide frames by sample rate for
seconds. Accepted sizes are capabilities, not proof of stable playback.
An unsupported rate is printed even though the tool can exit 0, so read the
output. `hw:0,1` is useful for queries but has no working playback route.

### pcm-floor: sustained playback periods

Exit games and players first. This tool needs exclusive access to `hw:0,0`,
so stop the audio services and their activation sockets. On the Nova:

```sh
(
  trap 'systemctl start pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service' EXIT
  systemctl stop wireplumber.service pipewire-pulse.socket pipewire-pulse.service pipewire.socket pipewire.service || exit
  pcm-floor --device hw:0,0 --rate 32000 --channels 2 --seconds 3
)
```

Repeat with `--rate 44100` and `--rate 48000`. Duration is per attempted
period, not for the entire sweep. The tool streams silence and prints asked
period, granted frames, buffer frames, sampled ALSA delay and underruns
(`xruns`). The first sustained period is a useful starting point; longer
runs under load are still needed. The printed latency is PCM queue delay,
not application-to-speaker latency, and the floor may be imposed by driver
parameters rather than the DSP. See [audio measurements](../docs/audio-latency.md).

For the live audio graph, `pw-top` shows rate, quantum and errors, while
`wpctl status` shows devices and routing. A follower's requested quantum is
not necessarily the quantum the driver is running.

## Automatic device checks

From the host repository root:

```sh
tools/device-tests root@nova
tools/device-tests root@nova game snes
```

The second command assumes a SNES game is already running; it does not launch
one. The script prints PASS, FAIL or SKIP with test IDs from the
[test plan](TEST_PLAN.md), then totals. A nonzero exit means a check failed.

Some expectations predate automatic VRR and newer audio changes, including
fixed per-system refresh rates. Treat failures as observations to investigate
against the current configuration, not a reason to restore obsolete settings.
This checker does not replace game compatibility testing or human checks of
picture, sound and controls.

## Keep the evidence

Copy the report to your computer before reflashing. From the host:

```sh
scp -r root@nova:/storage/debug-report ./nova-debug-report
scp -r root@nova:/storage/perf/baseline ./nova-perf-baseline
```

Attach the build identity, exact command, raw output and reproduction steps
to a report. For display runs, retain all files with the run prefix; for
audio, retain device, rate, granted period and xrun count. Note what was
deliberately changed and return those settings to their previous values
after the experiment.
