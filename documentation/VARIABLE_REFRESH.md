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
  writes `AVR_TRIGGER` after every commit. Its DSI code has no Qsync
  handling: the DSI controller follows the INTF.
- **Kernel patch 1097** adds that, off by default.
  `msm.dpu_avr_min_fps` sets the floor in Hz and is read at mode set.

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

## Running the AVR test

On a build with patch 1097. `vrr-probe` is in the debug set, which only
unofficial builds carry; elsewhere, copy the static build to `/storage`.

```
systemctl stop portarelauncher
echo 96 > /sys/module/msm/parameters/dpu_avr_min_fps
vrr-probe /storage/vrr-avr.csv 10 dynamic
echo 0 > /sys/module/msm/parameters/dpu_avr_min_fps
vrr-probe /dev/null 1 reset
systemctl start portarelauncher
```

The kernel logs `intf1: variable refresh, 1116 to 1397 lines a frame`
when AVR is on. The big digit is the phase, 7 to 14, and the grey number
the rate (0 for a pattern). Watch the dark grey patches for flicker,
especially in phase 11, where the frame length alternates every frame,
and compare brightness with phase 7. Then repeat at minimum brightness.

## Do not

Do not write the DPU's timing registers from userspace. Writing
`INTF_VSYNC_PERIOD_F0` on INTF 1 (0xae3600c) with `devmem` while the panel
ran rebooted the Nova, with no record of why. Use mode setting, or the
kernel patch.
