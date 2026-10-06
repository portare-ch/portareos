# Notes from armada-os/armada

What a read of the armada repository (a Fedora bootc image with
ROCKNIX-derived device support, `main` at 934b614, 27 September 2026)
turned up that bears on the Nova. Kept here so the ideas are not lost
when the survey scrolls away. Each item says where it lives there,
why it matters here, and what we did with it. Their
`packages/kernel/PATCHES.md` records the provenance of every patch,
which makes cherry-picking easy.

Nothing in armada covers RetroArch, a launcher, ScummVM,
mpv or panel refresh modes; its display work is gamescope and HDR.

## Taken

| Item | armada | Ours |
|---|---|---|
| 8bpc output dither: the DPU disables dithering at 8bpc, so a 10-bit result is truncated onto the panel; a panel opts in per DT property | `patches/0049-drm-msm-dpu-panel-opt-in-8bpc-dither.patch` (armada-authored) | kernel patch 0049 verbatim, `armada,dpu-8bpc-dither` on the Nova panel (#370) |
| Gamepad MCU on `vdd_mcu_3v3`, rail not always-on, rsinput releases it across suspend | `1007-input-rsinput-drop-the-mcu-supply-across-system-sleep.patch`, `dts/qcs8550-ayn-common.dtsi.patch` | patch 1014, DT change, HTR3212 driver with PM ops from ROCKNIX SM8750 (#370) |
| Stick calibration through rsinput module parameters | `apply-input-calibration` + `input-calibration.json` | we already shipped GPcal; fixed its pad name and wrapper (#370) |

## Suspend and sleep power

armada's commit 431bf57 reports Nova sleep power on USB input falling
from 0.67 W to 0.27 W with the following together. The MCU rail above
is one part; the rest is open here and relevant to the overnight drain
item (#62).

- **PCIe D3cold** (`0522-PCI-host-common-let-only-endpoints-veto-d3cold.patch`,
  armada-authored). The generic PCI host asks every device in the
  hierarchy whether D3cold is possible; the root port, still in D0,
  says no, so the PCIe controller, PHY and clocks stay on through
  s2idle. The patch lets only endpoints (the WCN7850) answer. Removes a
  spurious veto rather than adding one. Risk: Wi-Fi must return from
  D3cold on resume, which our PCIe suspend patches already exercise.
- **Codec rails in LPM during s2idle**: `regulator-state-mem` with
  `regulator-on-in-suspend` and `RPMH_REGULATOR_MODE_LPM` on
  `vreg_l15b_1p8` and `vreg_bob1`. We have the enabling driver patches
  (our 0218 and 1047) and use them for bob2 and the fan, not for these.
- **ADSP sleep with audio open at suspend** (`0528`, `0529`, `0530`,
  ASoC sc8280xp card PM ops and AudioReach graph release across
  suspend). Measured on an Odin 3 as about 0.09 W when a stream was
  open at suspend. The launcher, RetroArch or mpv can hold a PipeWire
  stream at suspend. armada then raised its PipeWire min-quantum to
  1024 against post-resume crackle; that part conflicts with our
  256-frame quantum.
- **tsens lower-threshold IRQs masked across suspend** (`0204`): a more
  targeted version of our 0203, which skips arming the whole uplow IRQ.
- **IPCC summary IRQ masked only for suspend-to-RAM** (`0504`): keeps
  `IRQF_NO_SUSPEND` and masks unlazily for s2ram only, scoped to
  SM8550/SM8750, said to stop cable-attach wakes on the AYN Thor. Our
  0502 removes `IRQF_NO_SUSPEND` outright.
- **ICE clocks unwound on resume failure** (`0510`); our 0207 already
  matches their 0511 (UFS IRQ on host reset failure).
- **iommu-map cell count** (`0514` upstream by Mani Sadhasivam, plus
  `0514a`): with five-cell `iommu-map` entries the fixed four-cell
  stride misprograms BDF to SID and, with `fw_devlink.strict=1`, links
  PCIe to random CoreSight nodes. We boot with `fw_devlink.strict=1`.
  Check the sm8550 dtsi before the next kernel bump.
- **Wake ledger** (`system-sleep/40-armada-wake-ledger`): 20 lines
  appending `pm_wakeup_irq`, the interrupt name and a timestamp to a
  log on every resume, since the kernel keeps only the last wake. We
  record nothing about wake reasons. Trivial, and the first thing to
  add when #62 is worked.
- **Sleep tracer** (`armada_sleep_debug.py`, 1391 lines): a per-cycle
  ftrace instance over power, rpm, clk, regulator, interconnect
  `icc_set_bw`, `rpmh_send_msg` (filtered to the sleep and wake sets)
  and UFS events, then a report. Heavy, but the event list is a recipe.
- **Fan supply in suspend**: their powerd sets pwm-fan `pwm1_enable` to
  3, cutting the fan supply at duty 0 and in suspend. We rely on
  `regulator-off-in-suspend` on the fan regulator instead. Probably
  equivalent; worth one measurement.
- Already equivalent: dwc3 USB autosuspend (our `81-usb-runtime-pm.rules`),
  PCIe L23 skip (our 0215), PCIe suspend OPP (our 1048/1049), geni UART
  IRQ masking (our 1006), rsinput quiesce (our 1004), UART frame
  reassembly (our 1013).

## Charging

- Their `0903` exposes the charge current limit as our 0510 does. Their
  note adds: writing 0 stops battery charging while USB keeps powering
  the system, which is bypass charging. A "bypass while docked" option
  would be one line in `charge-throttle` if the Nova firmware behaves
  the same.
- `armada-charge-debug`: a one-shot charging diagnostic (sysfs, journal,
  the `QCOM_PMIC_PDCHARGER_ULOG` firmware log). `0900` logs the USB
  adapter type when it changes.

## Display and colour

- **LUTDMA IGC and 3D gamut LUT** (`0068` to `0070`, 1515 lines): an
  independent implementation of what our never-run 1070/1071 do,
  verified on an Odin 2 Portal. Facts their notes record, to check
  ours against: IGC components ordered G, B, R; 257 samples at i/256,
  so the 256-entry LUT is resampled; command buffers rewritten in
  place, so an update waits on the done bit; in-flight marks dropped on
  runtime resume. They also expose the 17^3 gamut as a CRTC blob, which
  we do not.
- **DSPP joins the topology only on a modeset** (from their gamescope
  patch 0017): colour management on the CRTC needs a modeset when it is
  switched on or off. Relevant to how the launcher applies a profile.
- **DSI brightness transfer** (`0016-rp5-smooth-brightness-adjustment.patch`,
  generic despite the name): `msm_dsi_host_xfer_prepare()` re-cycles
  link clocks on every DCS transfer while the display is on, cutting
  the byte and pixel clocks mid-frame and underflowing the HS FIFO. Our
  Nova panel driver sends a DCS command per brightness step. Try it if
  brightness changes ever glitch the picture.
- **DP audio prepare while the display is off** (`0618`): a failing
  prepare made PipeWire drop the whole card profile, losing speaker and
  headphone sinks too. Directly relevant to our unverified HDMI sink
  switch, since Nova HDMI is USB-C DP.
- **Nova firmware**: their rp6 DTS points ADSP, `adsp_dtb`, AW883xx and
  `battmgr.jsn` at files extracted from a Pocket 6 vendor image rather
  than the Odin 2 fallback ours still names. Relevant to the audio
  topology our link-rate patches run against and to charger behaviour.
  The blobs are vendor licensed.
- **Stale jack report on removal** (`0064`, wcd-mbhc, shared with our
  codec): only if the Nova ever shows a stuck headphone state.
- Mesa 26.2.3 workarounds for A740 translation-fault storms
  (`disable-turnip-sparse-sync`, `ir3-disable-bindless-ubo-const-lowering`):
  candidates if Vulkan cores ever show SMMU faults.

## Input

- **Haptics** `1003`: the rumble bridge slept under `event_lock`
  ("scheduling while atomic" on every rumble stop, intermittent
  lockups on an Odin 3); mutex, deferred work, workers cancelled on
  suspend. Compare against our 1005.
- **Haptics** `1004`: the periodic-sine patch (our 1002 is the same)
  leaves a 5-second delayed brake tap after rumble ends. We likely share
  it.
- `axis-deadzone` DT property for all four stick axes (`1300`); the
  Nova DTS there uses trigger deadzones only, as ours does.
- Volume-up is not a wake source there (`wakeup-source` removed from
  KEY_VOLUMEUP); ours keeps it.

## Wi-Fi after resume

- NetworkManager `0002` and wpa_supplicant `0001/0002` (Collabora): scan
  only the last-associated channel after resume. We use iwd, so only
  applicable if the backend changes.
- ath12k `1020`: `cmd->scan_priority` never assigned, so every host scan
  goes out as VERY_LOW and is refused while the 11d scan is pending;
  reassociation took 4.4 to 8 s with iwd. Same WCN7850, same iwd here.

## Power and performance policy

Informational; opposite choices to ours in places.

- IRQs pinned to cores 3 to 7 on SM8550 with the note "the A740 GMU
  wedges if a GPU interrupt wakes CPU 0-2 out of power collapse". We
  boot with `irqaffinity=0-2`. Worth knowing when chasing GPU hangs.
- `conservative` governor for eco and balanced, per-policy underclock
  tables, fan curves as temp:pwm pairs with smoothing. We run schedutil,
  teo and a `fancontrol` curve.
- Kernel: `SCHED_CLASS_EXT` with scx_lavd, `UCLAMP_TASK`, `LRU_GEN`,
  `PSI`, `NTSYNC`. A udev rule copies GPU and GMU devcoredumps before the
  kernel's 5-minute auto-delete; we capture none.
- bfq plus `read_ahead_kb=4096` on mmcblk; we set bfq only.

## Build and process

- CI computes a content hash per package, checks the registry for an
  image with that tag and builds only the missing ones, one job per
  package on arm64 runners. Our incremental nightly restores saved
  state; the hash-as-tag idea is the only new element.
- `tests/` holds about 48 shell and Python tests run by `just check`,
  among them a UCM duplicate check and a power-button suspend hook test.

## Access

GitHub's API and HTML were not reachable from the session; the survey
worked from a shallow clone of `main`. Older history, issues and pull
request discussion were not read.
