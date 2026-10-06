# Power while nothing runs (SM8550)

What the Retroid Pocket Nova costs while no game runs: in the launcher with
the panel blanked, and suspended. Measured on 2026-10-03, build `6f8d1b3`, on
battery (the gauge reads 0 on a charger), with `idle-probe` and the battery's
charge counter. #496 holds the discussion.

## Summary

| State | Draw |
|---|---|
| Launcher idle, panel blanked | 0.95-1.0 W, about 250 mA |
| Suspended (s2idle) | 54-200 mA, about 60-80 mA overnight |

Suspend saves between a quarter and three quarters, and the CPU settings below
change nothing measurable. The SoC never reaches its system-level low-power states, awake or
suspended, and that, not the CPUs, is where the draw is. See "The SoC never
sleeps".

## CPU settings: no measurable effect

Launcher idle, panel blanked, eight 8-minute phases alternating, battery
current and voltage every 2 s:

| Configuration | Run 1 | Run 2 | Mean |
|---|---|---|---|
| schedutil, all cores online (today) | 1.005 W | 0.982 W | 0.994 W |
| cores 3-7 offline | 0.955 W | 1.031 W | 0.993 W |
| cores 3-7 capped at their minimum clock | 0.991 W | 0.991 W | 0.991 W |
| powersave on every cluster | 0.974 W | 0.967 W | 0.971 W |

The configurations differ by less than one configuration differs between its
two runs. `powersave` is at most 2 % lower, within that spread. Parking cores,
capping clocks and a different governor are therefore not worth carrying for
the launcher or PORTAMP.

## Wake-ups

Per thread, over 5 minutes, launcher idle, panel blanked
(`idle-probe` lists the same):

| Source | Wake-ups | Note |
|---|---|---|
| inputplumber, 5 threads | about 1300/s | follows the gamepad MCU's report stream |
| UART kworker (`ttyHS-qcom_geni_uart`) | 110/s | the gamepad MCU, a report every 9 ms |
| `thermal_events` kworkers | about 140/s | |
| schedutil kthreads (`sugov`) | about 80/s | |

The timer tick runs at about 4500 interrupts per second across the cores. Cores
0 and 1 (A510) almost never enter their deep idle state: since boot, core 0 had
2.88 million WFI entries against 129 power collapses. Cores 3 and 7 do reach
it.

**The gamepad stream:** the MCU waits `frame_rate` x 100 us after each scan
(`rsinput.frame_rate`, writable at runtime since kernel patch 1079). At 200
the UART interrupts drop from 110/s to 4/s and inputplumber goes quiet, but
the device draws only about 14 mW less (0.962 against 0.948 W, two runs
each). Real, but small next to the rest; not worth a screen-state hook yet.

## Suspend

20 minutes idle with the panel blanked, then 20 minutes suspended through
`systemctl suspend`, woken by the RTC alarm. Both by the battery's charge
counter:

| | Charge | Average |
|---|---|---|
| idle, panel blanked | 85402 uAh in 1200 s | 256 mA |
| suspended (`PM: suspend entry (s2idle)` ... `suspend exit`) | 57170 uAh in 1214 s | 170 mA |

That suspend was a bad one. The sleep ledger (`/storage/.cache/sleep-ledger.log`,
one line per suspend) shows the same kernel drawing 54 to 200 mA asleep: about
60 mA overnight on 09-28 and 09-29, 69 mA over 5.5 hours on 10-03. What makes
the difference is not known yet.

## The SoC never sleeps

`/sys/kernel/debug/qcom_stats` counts how often the platform enters its
low-power modes. After about three hours of uptime, including the 20-minute
suspend:

| Stat | Count |
|---|---|
| `cxsd` (CX rail collapse) | 0 |
| `aosd` (AOSS sleep) | 0 |
| `ddr` (DDR low-power modes) | 0 |
| `apss` (the CPU subsystem) | 1, during the suspend |

So the CPUs do their part and the platform underneath never powers down. One
cause is in the kernel log: two clock controllers never get their
`sync_state()` call, so every clock and vote the bootloader left on stays on:

    gcc-sm8550 100000.clock-controller: sync_state() pending due to 1d88000.crypto
    gcc-sm8550 100000.clock-controller: sync_state() pending due to 3d6a000.gmu
    gpu_cc-sm8550 3d90000.clock-controller: sync_state() pending due to 3d6a000.gmu

- `3d6a000.gmu` is the GPU's management unit. The Adreno driver used it
  without binding a driver to the device, so its suppliers waited for it
  forever. Kernel patches 1081-1085, Akhil P Oommen's "drm/msm: Attach a
  driver to GMU" series, give it one.
- `1d88000.crypto` is the UFS inline crypto engine, not the general one
  (QCE, `crypto@1dfa000`). Nothing uses inline encryption, so the device
  tree disables it rather than building its driver.

On build `18e3273`, with both, gcc and gpu_cc report `state_synced` and the
pending lines are gone, but nothing changed measurably: 1.015 W idle with the
panel blanked, and 80 mA over a 10-minute suspend, within the old spread.
`cxsd`, `aosd` and `ddr` stay 0.

The one known vote that holds the platform up in suspend is deliberate. With
the Wi-Fi link in D3cold, kernel patches 1048 and 1049 set the PCIe
controller's suspend OPP through s2idle: a 250 MB/s DDR and LLCC bandwidth
vote, and a request for `low_svs` on CX. Without that vote the firmware never
returned from `cluster_sleep_1` on the AYN Thor and the Retroid Pocket 6.
The Nova is no different. With the vote dropped (`pcie_qcom.suspend_floor=N`,
kernel patch 1086) it restarted by itself instead of resuming, so the floor
stays and CX and DDR collapse in s2idle is out of reach with this firmware
(#505). The switch is runtime-only, so the restart brings the floor back.

Awake, the CPU subsystem itself never reaches its system-level idle (`apss`
stays 0), so the platform cannot collapse whatever the votes.

## What Android does on the same board

2026-10-06, the Nova booted into its stock Android 13 (kernel 5.15.123,
Qualcomm's downstream), read over adb without root. The dumps and the
decompiled device tree are kept outside the tree in `~/1234/android/power`.
What they settle, and what they cannot:

- **Android suspends with `s2idle` too**, `/sys/power/mem_sleep` =
  `[s2idle] deep`. The sleep mode is not the difference.
- **Android's Wi-Fi is not a PCIe device the CPU owns.** It runs under
  Qualcomm's CNSS driver (`qcom,cnss-qca-converged`), and its rails are
  handed to the PDC: `qcom,vreg_pdc_map = "s4e" "rf", "l15B" "rf", "l3g"
  "rf", "s4g" "rf", "s6g" "rf", "s2g" "bb", "s5g" "bb"`, with
  `qcom,pdc_init_table` giving each an up and down value per sleep state.
  `s4g` and `s6g` are the same RPMh rails our `wcn7850-pmu` names as
  `vreg_s4g_1p3` and `vreg_s6g_1p8`. On Android the hardware sequences
  them with the WLAN's own sleep state; on ours the CPU does, through
  regulator calls, and a rail the CPU must hold is a rail that keeps CX up.
- **Android's PCIe controller runs PCIe DRV.** `qcom,pci-msm` with
  `qcom,drv-name = "lpass"` and `qcom,drv-l1ss-timeout-us = <5000>`: in
  suspend the audio DSP takes the link and parks it in L1ss, and the CPU
  subsystem collapses underneath it. That is the mechanism our suspend
  OPP vote stands in for. Mainline `pcie-qcom` has no DRV, so the vote
  (patches 1048, 1049) is what keeps the firmware from losing the link,
  and dropping it restarts the device (#505). The vote holds DDR and CX
  up for the whole sleep. Android does not pay that.
- **Its cluster idle tree has `llcc-off`** (`arm,psci-suspend-param
  0x4100c344`) above `l3-off` and `rail-pc`. Whether our tree offers the
  same states is a device-tree diff worth making when the device is back
  in PortareOS; the live tree can be read from
  `/sys/firmware/devicetree/base` the same way.
- **Not readable without root:** the SoC sleep counters. The devices exist
  (`c3f0000.soc-sleep-stats`, `c3f0000.subsystem-sleep-stats`,
  `17800054.cpuss-sleep-stats`) but expose nothing in sysfs, and
  `adb root` is refused on this production build. Whether Android reaches
  `cxsd` has to be inferred from its sleep current instead: the battery
  charge counter across an unplugged, screen-off period. Baseline taken,
  measurement pending.
- **Regulators enabled at idle on Android:** 13 of 95, read from
  `/sys/class/regulator`: `pm_v6e_s3_level(6) pm_v8_s5_level(1)
  pm_humu_l1(1) pm_humu_l5(1) pm_humu_l11(1) pm_humu_l15(4) pm_humu_l17(1)
  pm_humu_bob1(1) pm_v6e_s6_level(3) pm_v6e_s4(1) pm_v6e_l1(2)
  pm_v6e_l1_ao(1) pm_v6e_l3(3)`. The same read on PortareOS, idle with the
  panel blanked, is the next comparison to make.

**The same reads on PortareOS**, 2026-10-06, just booted, launcher idle,
`/sys/power/mem_sleep` = `[s2idle] deep`. Enabled regulators, 14 of 43:
`vdd_fan_5v0(1) vdd_disp_1v8(1) vdd_mcu_3v3(3) ts_vddio_1v8(1)
ts_avdd_3v0(1) vreg_bob1(1) vreg_bob2(1) vreg_s4e_0p95(3) vreg_l1e_0p88(2)
vreg_l3e_1p2(3) vreg_s2g_0p8(1) vreg_l15b_1p8(4) vreg_l17b_2p5(1)
vreg_l1d_0p88(1)`. Against Android's list by PMIC resource: `s4e`, `l1e`,
`l3e`, `l15b`, `l17b`, `l1d` and `bob1` are on in both. Ours also holds
`bob2` and `s2g_0p8`, and `s2g` is one of the rails Android's PDC map
drives for the WLAN (`"s2g" "bb"`), so on Android it follows the radio's
sleep state and here it is simply on. Android also shows `l5` and `l11`
on, which here are off or absent, and its `*_level` entries are power
domains, not regulators, so they do not compare. The five fixed GPIO
regulators (fan, display 1.8 V, MCU, touch) are ours alone; what the
suspend hooks do with them is the next thing to read, since this list is
the awake state.

Idle states: our tree has one rail-power-collapse state per cluster and
two domain states, `cluster-sleep-0` and `cluster-sleep-1`, against
Android's `rail-pc`, `l3-off` and `llcc-off` ladder. `cluster-sleep-1` is
the one the firmware would not return from without the PCIe vote (#505).
`qcom_stats` at boot: `apss` 1, `cxsd`, `aosd`, `ddr` 0, as before.

Charger: PortareOS reports `voltage_max` 4.40 V where Android charges to
4.50 V with a 5191 mAh design and 5060 mAh learned capacity; ours exposes
no design capacity. Whether the 4.40 V is a deliberate margin or a
default is not recorded anywhere in the tree.

What this means for #62: the gap is not a missing tweak. Android keeps
Wi-Fi alive through two pieces of hardware-assisted sleep that mainline
does not have, PDC-driven rails and PCIe DRV, and that is what lets its
SoC collapse with the radio up. Our options are to carry that machinery,
which is a driver project, or to make suspend not need the link at all:
radio fully off and the PCIe root port powered down, so that there is no
link for the firmware to lose and the vote can go. The tree already notes
that the radio is down in suspend for the driver's own reasons; whether
the root port can go with it, and the vote after it, was the experiment.

**Done, 2026-10-06, and the link is not what the firmware needs.** Build
`82d5282`, kernel 7.2.9, on battery, three s2idle suspends of 120 s each
with an RTC alarm, back to back, run detached and logged to `/storage`:

| Arm | PCIe state | Suspend floor vote | Resumed | `cxsd`/`aosd`/`ddr` |
|---|---|---|---|---|
| A | shipped: root port and Wi-Fi card present | kept | yes | 0 / 0 / 0 |
| B | Wi-Fi card removed, its power sequencer unbound, root port removed: no PCI devices at all | kept | yes | 0 / 0 / 0 |
| C | as B | dropped (`pcie_qcom.suspend_floor=N`) | **no, the device restarted** | boot counters, 0 |

The radio was taken down through `pci-pwrctrl-pwrseq` (unbind of
`1c00000.pcie:pcie@0:wifi@0`), which cuts the WCN7850 rails; two
regulators fewer were enabled afterwards. `qcom-pcie` itself cannot be
unbound, so the controller stayed probed with an empty bus. Rebinding and a
PCI rescan would have brought Wi-Fi back; the restart did it instead.

So the firmware's dependence on the suspend OPP vote has nothing to do with
a PCIe link: with no endpoint, no root port and the radio unpowered, dropping
the vote still lost the device in `cluster_sleep_1`. The vote is a 250 MB/s
DDR and LLCC sleep-set bandwidth and a `low_svs` request on CX (patch 1049),
and the next question is which of those the firmware actually needs. Kernel
patch 1089 splits the switch for that: `pcie_qcom.suspend_floor_bw=N` keeps
only the CX state, `pcie_qcom.suspend_floor_cx=N` only the bandwidth. Both
are runtime-writable under `/sys/module/pcie_qcom/parameters/` and not
persisted, so a failed resume costs a restart and nothing else.

Two things the result does not say. It does not say whether the kernel
resumed and crashed or the firmware never came back: until that build there
was no ramoops on this device, so a resume-side panic left nothing behind.
The Nova DTS now reserves 2 MB at `0xc0000000` for one (`CONFIG_PSTORE_RAM`
and `CONFIG_PSTORE_CONSOLE` built in) for exactly that. It held nothing,
after the restart or after a plain reboot, and was removed again; see
below. And it does not say what arm B saved: the battery gauge's
`charge_counter` did not move at all across arm A and dropped 3.2 mAh across
arm B, which is the gauge updating late, not a measurement.

**Done, 2026-10-06, build `cee17f8d`, with a correction to everything
above.** Those earlier arms, and the three of the day before, suspended by
writing `mem` to `/sys/power/state`. That skips systemd's sleep hooks, and
one of them matters: `096-cpuidle` disables cpu0's deep idle state at boot
for the GPU's sake, and `sleep.d/pre/004-cpuidle-state1` gives it back for
the suspend window. Without it cpu0 never leaves WFI, the CPU cluster's
power domain never enters its sleep state (`power-domain-cluster/idle_states`
in `pm_genpd` debugfs read 0 entries across seven suspends) and `apss` never
counts. So none of those arms ever reached `cluster_sleep_1`, which is the
state the firmware has to return from. They say less than they were taken
to say.

Through `systemctl suspend`, with the hooks running and an RTC alarm, 120 s
each, back to back:

| Arm | Vote kept in suspend | Cluster slept | Resumed | `cxsd`/`aosd`/`ddr` |
|---|---|---|---|---|
| A | both (shipped) | yes, `apss` 1 to 2 | yes | 0 / 0 / 0 |
| B | bandwidth only (`suspend_floor_cx=N`) | yes, `apss` 2 to 3 | yes | 0 / 0 / 0 |
| C | CX state only (`suspend_floor_bw=N`) | yes | **no, the device restarted** | boot counters |

So the half the firmware needs is the DDR and LLCC sleep-set bandwidth. The
CX `low_svs` request can go, and going without it changes nothing that can
be measured: `cxsd` stays at 0, so something else keeps CX enabled in the
sleep set. The candidates are in `pm_genpd_summary`: `gcc` holds CX with no
runtime PM at all (the 20260424 patch gave it the domain so GDSC votes
propagate), the PCIe controller holds `pcie_0_gdsc` for its wake line, and
every enabled subdomain keeps the parent at its enable corner, which since
patch 1090 is the first corner above retention. Finding which of those
survives into the sleep set is the next piece of work; the PCIe vote is no
longer in the way.

Two more things the run settled:

- **The retention backport (1090) did not make the drop survivable.** Arm C
  restarted on a build that carries it.
- **ramoops in DDR does not survive any reset on this device.** The
  region registered at boot and the console was logging to it, and after
  the restart `/sys/fs/pstore/` was empty with no "found existing buffer"
  line. The same after a plain `reboot` with the console zone full: the
  bootloader does not hand DDR back with its contents, warm or cold, so
  nothing written to RAM before a reset can be read after it. The ramoops
  node and the built-in pstore options went back out (they cost a
  non-cached write per console line for nothing). Two more facts from the
  attempt: a deliberate panic with `kernel.panic=5` did not restart the
  device, it hung until the power key was held; and 7.3's minidump
  addition is only the always-on SRAM word that tells the boot firmware
  where to deliver a minidump, while the driver that fills the minidump
  table is not in mainline, so backporting the word points at nothing.
  7.2.9 already has `qcom_scm.download_mode` with the TCSR cookie for a
  full dump into download mode; whether this bootloader honours it is
  untested, and a device parked in download mode needs the power key.

The same four arms were also run through `/sys/power/state` on this build
first, before the hook problem was found. All four resumed, including the
full drop that had restarted the device twice, and that is now explained:
with the cluster awake there is nothing for the firmware to return from.
The one restart that does not fit is the previous day's arm C, which also
bypassed the hooks and still restarted when the vote was dropped with no
PCIe device on the bus. That case is recorded as unexplained.

Suspend experiments from a script must go through `systemctl suspend`, or
run `sleep.d/pre/004-cpuidle-state1` by hand; `/sys/power/suspend_stats/
success` is the signal that the sleep completed, and the cluster count in
`pm_genpd` debugfs is the check that it was a real one.

## Measuring

    idle-probe [seconds]      on the device, default 300

It refuses on a charger or while a game runs, prints mean battery power,
interrupt, context-switch and deep-idle rates, and the threads that woke most.
For the overnight case, start it detached once the launcher has blanked the
panel (5 minutes without input):

    setsid idle-probe 600 >/storage/idle-probe.txt 2>&1 &
