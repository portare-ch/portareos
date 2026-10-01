# CPU layout and isolation (SM8550)

What the Retroid Pocket Nova's CPU looks like, how emulators are placed on it
today, and the plan for keeping the rest of the system off the cores a game
uses. Per-emulator layouts are in [emulators/](emulators/README.md).

## The SoC

QCS8550, the Snapdragon 8 Gen 2's layout, 1 + 4 + 3. Read from the device:
`/proc/cpuinfo` CPU part, `cpufreq/*/cpuinfo_max_freq`, `cpu_capacity` and
`cache/index*/shared_cpu_list`.

| Cores | Design | Part | Max clock | Capacity | cpufreq policy |
|---|---|---|---|---|---|
| 0-2 | Cortex-A510 | 0xd46 | 2.016 GHz | 222 | policy0 |
| 3-4 | Cortex-A715 | 0xd4d | 2.803 GHz | 657 | policy3 |
| 5-6 | Cortex-A710 | 0xd47 | 2.803 GHz | 657 | policy3 |
| 7 | Cortex-X3 | 0xd4e | 2.957 GHz | 1024 | policy7 |

The phone part's prime core runs at 3.2 GHz; this one tops out at 2.957.
Cores 3-6 share one clock domain, so an A715 and an A710 always run at the
same frequency. Of the two, the A715 is the newer and faster design.

Caches:

- **L1 and L2** are private to each core. Spec sizes, not exposed by sysfs:
  1 MB L2 on the X3, 512 KB on the A715/A710.
- **L3**, 8 MB, is shared by all eight cores, and behind it a system-level
  cache shared with the GPU.

Consequences:

- A thread that moves to another core refills its L2 from L3.
- Two threads exchanging data always do it through L3, wherever they sit.
  Placement cannot make that traffic cheaper. It can stop the refills.

## Clocks

The cpufreq governor is schedutil (`system.cpugovernor`, set at boot by
`autostart/008-perfmode`). Schedutil clocks a core from the utilization of
what runs on it. An emulator whose threads take turns within a frame looks
lightly loaded however full the frame is:

- PS2, NFSU, 2026-10-01: EE about 20% and GS about 20% under schedutil; cores
  3-6 swinging between 0.7 and 2.8 GHz; 40 fps.
- Cores 3-7 set to performance by hand, nothing else changed: 59.7 fps.

Today's answer is a per-system governor. runemu applies `<system>.cpugovernor`
at launch and restores `system.cpugovernor` on exit. `ps2.cpugovernor` ships
as `performance`. The `performance` function sets every cluster and the
memory controller, not only the cores the game uses.

The finer tool is utilization clamping: a `uclamp.min` on the emulator's hot
threads, so schedutil clocks and places them as busy while the rest of the
system keeps scaling. The kernel is built without it (`CONFIG_UCLAMP_TASK`).

## Placement today

- **Interrupts:** `irqaffinity=0-2` on the kernel command line keeps device
  interrupts on the A510s.
- **Process masks:** runemu starts an emulator under a mask from the quirk
  `040-affinity`, chosen by `<system>.cores`:
  - `little`: `SLOW_CORES`, 0-2.
  - `big`: `FAST_CORES`, 3-7; the default (bare `cores=big`).
  - `frontend`: `FRONTEND_CORES`, 5-6. For an emulator that pins its own hot
    threads; the rest of its process stays off those cores.
- **Thread pinning inside the emulator:** ARMSX2 pins EE to 7, VU1 to 3 and GS
  to 4; see [emulators/ARMSX2.md](emulators/ARMSX2.md).
- **Test:** `coremap-check` checks a running emulator's threads against its
  documented layout.

What none of this does: keep other processes off the game's cores. A mask set
with `taskset` only binds the process it is set on. The launcher, PipeWire,
systemd services and kernel worker threads can still be scheduled onto cores
3-7 during a game.

## Plan: cpuset isolation

### The obstacle

systemd confines a slice to cores with `AllowedCPUs=`, which works only on the
unified cgroup hierarchy. The project's systemd 255.22 is built with
`-Ddefault-hierarchy=hybrid` (`projects/PortareOS/packages/sysutils/systemd/package.mk`),
inherited from upstream without a stated reason. On the device the v1
controllers are mounted under `/sys/fs/cgroup/*`, and the cgroup2 tree at
`/sys/fs/cgroup/unified` offers `cpuset` and `memory` but is not managed. The
kernel is ready: `CONFIG_CPUSETS=y`, without `CPUSETS_V1`.

### Phase 1: unified hierarchy (done)

- systemd is built with `-Ddefault-hierarchy=unified`, upstream's default.
  `/sys/fs/cgroup` is then a single cgroup2 tree.
- Nothing in the tree reads v1 paths. The Docker addon uses the systemd
  cgroup driver, which runs on v2. The kernel has every controller systemd
  uses there: cpuset, cpu, memory, io, pids, and BPF for device control.
- One unit sets a device policy: `iwd.service` (`DevicePolicy=closed`). On v2
  that is a BPF program rather than the v1 devices controller. Wi-Fi is the
  first thing to check on a new image.
- Also check after flashing: every service starts (`systemctl --failed`), and
  suspend and resume work.

### Phase 2: a game slice

- A `game.slice` with `AllowedCPUs=3-7`.
- runemu starts the emulator in a transient scope in that slice
  (`systemd-run --scope --slice=game.slice ...`). The process mask (`taskset`)
  and the emulator's own pinning then work inside it. A cpuset bounds
  `sched_setaffinity`, so the slice must include every core the emulator
  pins to.
- While a game runs, runemu narrows everything else, and restores it on exit:
  - `system.slice` to `AllowedCPUs=0-2`, with `systemctl set-property
    --runtime`.
  - Unbound kernel workqueues to 0-2, through
    `/sys/devices/virtual/workqueue/cpumask`.
- Kernel threads bound to a core, and the scheduler's own work, stay where
  they are. That is the limit of what cpusets do without `isolcpus` or
  `nohz_full`, which would take cores from the system permanently.
- To decide: whether PipeWire belongs in `game.slice` or stays with the system
  on the A510s. Its real-time thread is light, but it sits on the audio path.
  Measure xruns both ways (`perf-probe`).

Rendering is KMS only, with no compositor during a game, so the system has
little left to run while a game is up. That is what makes taking cores 3-7
away from it cheap.

### Phase 3: a dedicated gaming user

Everything runs as root today, systemd is built without PAM, and the only
accounts are system ones. A `game` user that emulators run as would
separate privileges: an emulator or a port could no longer write the system,
change governors or read other users' data. It is not needed for phase 2: a
scope puts a process in `game.slice` whatever its uid. With phase 2 in
place, it adds security and makes the split structural rather than
something runemu arranges.

What it takes:

- **Privileges:** runemu stays root, since it writes governors and sysfs. It
  drops to `game` only when it executes the emulator (`setpriv` with the
  supplementary groups).
- **Device access:** groups for DRM (`video`, `render`), input and sound.
  udev rules must give those groups access to the nodes they need.
- **Storage:** ownership of `/storage` paths emulators write: roms, saves,
  config, cache. Mount options for removable media formatted vfat or exfat.
- **Audio:** PipeWire access for that uid.
- **Ports:** PortMaster and port scripts that assume root.
- **Account creation:** a static user, since `sysusers` is off in the systemd
  build.

### Order and checks

Phase 1, then 2, then measure, then decide on 3. For each phase:

- `coremap-check` must pass.
- `perf-probe` runs against the same game and scene must show the change.
- Measured on NFSU in a race (EE-bound) and on a VU-bound PS2 game.
