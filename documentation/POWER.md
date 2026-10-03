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
Removing it is the test that would show what full collapse saves on the Nova,
at the risk of a hang on resume (#505).

Awake, the CPU subsystem itself never reaches its system-level idle (`apss`
stays 0), so the platform cannot collapse whatever the votes.

## Measuring

    idle-probe [seconds]      on the device, default 300

It refuses on a charger or while a game runs, prints mean battery power,
interrupt, context-switch and deep-idle rates, and the threads that woke most.
For the overnight case, start it detached once the launcher has blanked the
panel (5 minutes without input):

    setsid idle-probe 600 >/storage/idle-probe.txt 2>&1 &
