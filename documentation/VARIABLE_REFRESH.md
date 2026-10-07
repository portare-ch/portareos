# Variable refresh on the Nova

The goal is integer-multiple variable refresh. Every game frame is
scanned exactly twice, and the panel follows the game at twice its rate:
PAL at 100 Hz, NTSC at 119.88 Hz, SwanStation's 59.826 at 119.652 Hz.
That needs no panel mode per console, and nothing outside 100 to 121 Hz.
The open question is whether the panel takes a frame length that changes
from one frame to the next inside that range.

## What the hardware offers

- **Android** drives the panel, an il97680a 4.5" 1280x960 AMOLED, in
  command mode with the TE pin. It has two timings, 120 and 60 Hz,
  switched by DCS register 0x60, and no Qsync properties or commands. The
  same device tree enables Qsync for Qualcomm's reference panels.
- **PortareOS** drives it in video mode (kernel patch 0105). The
  per-console modes change the pixel clock.
- **The DPU's INTF has AVR**, the block Qualcomm's downstream driver uses
  for Qsync in video mode: the vertical front porch runs on until a
  trigger, up to a set frame length. Mainline defines its registers and
  programs none. Downstream writes the longest frame to `AVR_VTOTAL`, sets
  bit 0 of `AVR_CONTROL` and bits 0 and 8 of `AVR_MODE` for one-shot, and
  writes `AVR_TRIGGER` after every commit. The SM8550 driver also sets
  `AVR_SUPPORT_ENABLE`, bit 29 of the DSI host's video mode control
  (`DSI_VIDEO_MODE_CTRL`, mainline's `REG_DSI_VID_CFG0` plus the 6G
  shift, 0xae94010 on the Nova), when it switches Qsync on.
- **Kernel patch 1097** adds that, off by default.
  `msm.dpu_avr_min_fps` sets the floor in Hz and is read at mode set:
  the DSI host sets bit 29 and the INTF gets the longest frame. The next
  commit switches AVR on, with the INTF in its flush, in the order
  downstream switches Qsync on. From DPU 8.1, bit 31 of `AVR_CONTROL`
  reads 1 while AVR is active.

## Measured, 2026-10-07

### A stretched front porch, static

`vrr-probe` static phases: the preferred mode's 156.24 MHz pixel clock and
a longer vertical front porch, set through ordinary mode setting.

| Rate | Front porch, lines | Frames in 10 s |
|---|---|---|
| 119.88 Hz | 12 | 1200 |
| 110 Hz | 102 | 1100 |
| 100 Hz | 211 | 1001 |
| 90 Hz | 344 | 901 |
| 80 Hz | 511 | 801 |
| 72 Hz | 678 | 721 |
| 60 Hz | 1011 | 600 |

Every rate ran exactly, with no DSI or DPU error. By eye, at normal
brightness, the picture was stable with no flicker at every rate. Low
brightness is not checked yet.

The panel's TE pin, GPIO 86, cannot be read as a GPIO: the pin controller
refuses it while the DSI holds it as `mdp_vsync`.

### Frames on a schedule, fixed refresh

`vrr-probe` dynamic phases on the 120.198 Hz mode, without AVR. The
start is the kernel's flip timestamp against the scheduled commit.

| Schedule | On the 8.32 ms grid | Start after schedule, median | Frame lengths |
|---|---|---|---|
| 120 Hz | 100% | 5.7 ms | 8.3 ms |
| 119.652 Hz | 100% | 6.3 ms | 8.3 ms |
| 110 Hz | 100% | 5.8 ms | 8.3 ms, 16.6 ms in 1 of 11 |
| 100 Hz | 100% | 5.8 ms | 8.3 ms, 16.6 ms in 1 of 5 |
| 100 and 120 alternating | 100% | 5.8 ms | 8.3 ms, 16.6 ms in 1 of 10 |
| Random, 8.34 to 10 ms | 100% | 5.6 ms | 8.3 ms, 16.6 ms in 1 of 10 |
| Game frames of 16.7 to 20 ms, each twice | 100% | 5.7 ms | 8.3 ms, 16.6 ms in 1 of 10 |

With AVR the same schedules should start frames off the grid, within
about a millisecond of each commit, and the frame lengths should follow
the schedule.

### AVR switched on at mode set: inactive

The first version of patch 1097 enabled AVR at mode set, before the
timing engine started. The registers read back as programmed:
`AVR_CONTROL` 0x1, `AVR_MODE` 0x101, `AVR_VTOTAL` 1250 lines. The status
bit stayed clear, frames ran at 119.98 Hz with no commits instead of the
96 Hz floor, and every dynamic schedule landed on the 8.32 ms grid as on
the fixed refresh. No flicker was seen, but on fixed timing.

Switched on in the first commit after the mode set, with the INTF in
that flush, it stayed inactive the same way: status bit clear, 119.5
frames/s with no commits. The DSI host's `AVR_SUPPORT_ENABLE` was still
clear (`0x10009130`); the patch now sets it.

With the DSI bit set (`0x30009130`), AVR stayed inactive again: status
bit clear, 120.5 frames/s with no commits. One difference left in plain
sight: downstream always enables programmable fetch in video mode, at
least one line ("prog fetch always enabled case"); mainline turns it off
when the back porch is long enough, as here (`PROG_FETCH_START` 0). The
patch now carries that and the other candidates as parameters, so one
build can try them all:

| Parameter | Default | What it changes |
|---|---|---|
| `dpu_avr_prog_fetch` | 1 | Programmable fetch lines while AVR is wanted, where the porches need none |
| `dpu_avr_continuous` | N | Continuous AVR instead of one-shot |
| `dpu_avr_at_modeset` | N | Switch AVR on at mode set instead of in the first commit |
| `dpu_avr_flush_intf` | N | Flush the INTF on every commit |
| `dpu_avr_dsi` | Y | The DSI host's AVR support bit |

All are under `/sys/module/msm/parameters/` and are read at mode set,
except `dpu_avr_flush_intf`, which is read every commit.

## Running the AVR test

On a build with patch 1097. `vrr-probe` is in the debug set, which only
unofficial builds carry; elsewhere, copy the static build to `/storage`.

First, whether AVR holds the front porch at all. `idle` commits once
and then nothing, so frames should slow to the floor:

```
systemctl stop portarelauncher
echo 96 > /sys/module/msm/parameters/dpu_avr_min_fps
vrr-probe /dev/null 6 idle &
sleep 2
devmem 0xae36270 32          # 0x80000001: AVR active
F=0xae360ac; a=$(devmem $F 32); sleep 2; b=$(devmem $F 32)
echo $(( (b - a) / 2 )) frames/s   # about 96, not 120
wait
```

Then the schedules:

```
vrr-probe /storage/vrr-avr.csv 10 dynamic
echo 0 > /sys/module/msm/parameters/dpu_avr_min_fps
vrr-probe /dev/null 1 reset
systemctl start portarelauncher
```

At the mode set the kernel logs `intf1: variable refresh, 1116 to 1397
lines a frame`. The big digit is the phase, 7 to 14, and the grey number
the rate (0 for a pattern). Watch the dark grey patches for flicker,
especially in phase 11, where the frame length alternates every frame,
and compare brightness with phase 7. Then repeat at minimum brightness.

## Do not

Do not write the DPU's timing registers from userspace. Writing
`INTF_VSYNC_PERIOD_F0` on INTF 1 (0xae3600c) with `devmem` while the panel
ran rebooted the Nova, with no record of why. Use mode setting, or the
kernel patch.
