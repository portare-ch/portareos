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

A mask set with `taskset` only binds the process it is set on. Keeping the
launcher, PipeWire, systemd services and kernel worker threads off a game's
cores is phase 2 below.

## Plan: cpuset isolation

### The obstacle

systemd confines a slice to cores with `AllowedCPUs=`, which works only on the
unified cgroup hierarchy. The project's systemd 255.22 is built with
`-Ddefault-hierarchy=hybrid` (`projects/PortareOS/packages/sysutils/systemd/package.mk`),
inherited from upstream without a stated reason. On the device the v1
controllers are mounted under `/sys/fs/cgroup/*`, and the cgroup2 tree at
`/sys/fs/cgroup/unified` offers `cpuset` and `memory` but is not managed. The
kernel is ready: `CONFIG_CPUSETS=y`, without `CPUSETS_V1`.

### Phase 1: unified hierarchy

- Build systemd with `-Ddefault-hierarchy=unified`.
- Audit everything that reads v1 paths. In the tree that is only the Docker
  addon, which uses the systemd cgroup driver and runs on v2.
- Check on the device that every service still starts, and that suspend and
  resume (which may use the freezer) still work.

### Phase 2: a game slice (done)

The quirk `040-affinity` names the two sets: `GAME_CPUS=3-7` and
`SYSTEM_CPUS=0-2`.

- **The emulator:** runemu starts it in a transient scope in `game.slice`
  (`systemd-run --scope --slice=game.slice -p AllowedCPUs=3-7`). The scope
  execs the command in place, so the emulator keeps runemu's pid tree, and
  the pid file and `kill_tree` work as before. The process mask (`taskset`)
  and the emulator's own pinning apply inside the scope.
- **Everything else, while the game runs:**
  - `system.slice` goes to `AllowedCPUs=0-2`, with `systemctl set-property
    --runtime`. That includes the launcher and runemu itself.
  - The kernel's unbound workqueues go to 0-2, through
    `/sys/devices/virtual/workqueue/cpumask`.
- **Restore:** on exit, and from an `EXIT` trap, so a run killed with TERM
  restores too. A KILL leaves only `--runtime` state, which a reboot clears;
  the next game's exit also restores it.
- **When it is skipped:**
  - On the hybrid hierarchy, or when the quirk names no sets.
  - With `<system>.cpuisolation=0`, per system or per game.
  - For a system set to `cores=little`. A cpuset bounds `sched_setaffinity`,
    so `taskset -c 0-2` inside a scope on 3-7 would fail to start the game.
    For the same reason the scope has to include every core an emulator pins
    to.
- **Limits:** kernel threads bound to a core, and the scheduler's own work,
  stay where they are. That is as far as cpusets go without `isolcpus` or
  `nohz_full`, which would take cores from the system permanently.
- **Open:** PipeWire is a system service, so it runs on the A510s during a
  game. Its real-time thread is light, but it sits on the audio path. Compare
  xruns with it in `game.slice` (`perf-probe`).
- **Test:** `coremap-check` also checks this on the unified hierarchy: the
  emulator must be in `game.slice`, and `system.slice` must not reach the
  emulator's reserved cores.

Rendering is KMS only, with no compositor during a game, so the system has
little left to run while a game is up. That is what makes taking cores 3-7
away from it cheap.

### Phase 3: a dedicated gaming user (opt-in)

`system.gameuser=1` makes runemu start every emulator as the user `game`
(uid 1000, group `games`) instead of root. It is off by default. It is one
switch for every system on purpose: an emulator still run as root must not
read a file another one could write as `game`.

What is in place:

- **Accounts:** `game` and `games` (portareos package). `game` is a member of
  `video`, `audio`, `input` and `render` (systemd), and of `pipewire`, for
  the system socket (`SocketGroup=pipewire`).
- **Privilege drop:** util-linux `setpriv --reuid=game --regid=games
  --init-groups`, built against libcap-ng (static). It execs argv in place
  and sets the supplementary groups. Two other tools fall short here:
  - `systemd-run --uid=` sets uid and gid but not supplementary groups
    (`run.c`), so the game could not open the device nodes.
  - busybox's `setpriv` changes no uid at all.
- **Writes, an allowlist,** granted to `games` before each launch (group
  write, setgid on directories):
  - Everything under `/storage/roms` except `backup`/`backups`. Root restores
    those, so a planted archive could write anywhere.
  - The emulators' own config directories: `retroarch`, `xemu`, `mpv`,
    `portamp`, `PortMaster`.
  - `/var/log/retroarch`.
  - A cache of its own, `/storage/.cache/game`, as `XDG_CACHE_HOME`.
    `/storage/.cache` itself holds the shadow file.
- **What root keeps for itself:** nothing root sources or executes is on the
  list, and none of it becomes writable: `system.cfg` (runemu executes
  setting values such as `cpugovernor`), `profile.d`, `autostart`,
  `system.d`.
- **The grant cannot be turned against root:** it runs as root over paths
  `game` can write. It never follows a symlink, and it touches only files
  with one link, so a link planted to `system.cfg` cannot hand it over.
- **SD cards:** FAT and exFAT are mounted `gid=1000,umask=0002`, files
  group-writable for `games`. This applies whether or not the switch is on;
  root's access is unchanged.

What is not settled, and why it is opt-in:

- **KMS:** a non-root process becomes DRM master only if no master exists
  when it opens the device. The launcher drops master before runemu runs,
  which should be enough. Not tried.
- **Input:** `/dev/uinput` is root-only, so ports that use `gptokeyb` will
  not get their key mapping. Rumble and LED sysfs writes, if any, likewise.
- **Standalones:** xemu and Steam may write outside their config directory.
- **Root-side readers:** scripts that read game-writable files have to treat
  them as data. `setsettings.sh` edits `retroarch.cfg` and the core options
  with `sed`; it needs an audit for `eval` and command substitution on
  values read back.
- **Not tried on the Nova at all.** Checklist: switch it on; then run a
  RetroArch system, PS2, a port, xemu, mpv and portamp; save to internal
  storage and to an SD card.

### Order and checks

Phase 1, then 2, then measure, then decide on 3. For each phase:

- `coremap-check` must pass.
- `perf-probe` runs against the same game and scene must show the change.
- Measured on NFSU in a race (EE-bound) and on a VU-bound PS2 game.
