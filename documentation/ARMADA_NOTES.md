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
| Stick calibration through rsinput module parameters | `apply-input-calibration` + `input-calibration.json` | GPcal shipped with its pad name and wrapper fixed (#370), then dropped with pyxel; rsinput's parameters remain |
| GMU HFI interrupt clearing the reply and OOB ack bits it does not own, unbounded devcoredump wait, HFI interrupt unmasked before GMU boot | `0620`, `0621` (from Kettle), `0622` | patches 1099-1101; `096-cpuidle` and its hooks removed (#602) |
| UFS lane clock helpers enabling every clock, geni UART kept active across sleep (upstream backports) | `0533`, `0534` | patches 1102, 1103 (#603) |
| ath12k scan priority never sent, scan timeout deadlock | `1020`, `1021` | patches 1104, 1105; 1106 and the timezone's country are ours |
| GPU submitqueue priorities mapped onto HIGH through LOW, keeping KERNEL for VM_BIND | kernel `0619` | kernel patch 1113; imported, device verification pending |
| libliftoff stacking across multiple primary planes | gamescope `0020` | gamescope patch 0009, including its nine regression cases; imported, device verification pending |

## Steam: checked again on 18 October 2026

Checked [armada at `4c945ec5`](https://github.com/armada-os/armada/tree/4c945ec5b28176c8580059a1c5ab6176ac5f3104)
against our Gamescope `2b5cf191`, its libliftoff `8b08dc1c`, kernel 7.2.11,
Steam launcher and installer. Kernel `0619` and Gamescope `0020` are now
imported as recorded above; neither has been measured on the Nova. The
remaining changes below are an import assessment.

The kernel fix applies to both affected 7.2.11 files and corrects an
inversion that can give an ordinary Turnip queue kernel priority above
Xwayland's GL queue. Armada reports compositor starvation under GPU load.
It changes scheduling for every GPU client, so compare Steam and Vulkan
emulators before calling the device behavior verified. Both affected kernel
objects, `msm_submitqueue.o` and `msm_gpu.o`, compile in Linux with the Nova
config on 7.2.11. A check using the actual conversion helper and entity-index
expression passes 42 priority and range cases; the original mapping fails,
and omitting the entity-index correction fails separately.

The libliftoff fix keeps Steam and external overlays above an opaque game
when the DPU scans layers out on separate primary planes. It applies to
our exact submodule: five of its nine new cases fail before the fix, and
a clean Linux build with the fix passes all 67 tests, including the
existing suite. Overlay order and direct scanout still need a Nova test.

### Candidates

| Change there | Value here | Assessment |
|---|---|---|
| Gamescope `0024`, report native Wayland windows to Steam | A game with an xdg-shell window can remain behind Steam's launch spinner because only Xwayland windows are reported as focusable. Publishes the Wayland window's app ID and PID too. | Applies after our current patches. Useful when adding native Wayland games or Proton's Wayland driver; verify launch, focus, overlay and return to Steam. Our launcher would also need to expose Gamescope's Wayland socket deliberately. |
| Gamescope `0025`, native Wayland touch passthrough | Lets an xdg-shell application receive touch rather than Steam's emulated mouse clicks, retaining passthrough for that touch until it ends. | Applies with `0024`. Conditional on supporting native Wayland applications; test touch across focus changes and keep X11 mouse emulation working. |
| Gamescope `0018`, ARM64 virtual white | Recovers the missing white-point component from the ARM Steam client's packed property, making its color-temperature slider effective. | Applies directly. Needs the Steam color-management capability flags and on-device verification, including direct scanout. It does not supply the DPU color pipeline by itself. |
| `launch-steam`, preserve `SYSTEM_PATH` and `SYSTEM_LD_LIBRARY_PATH` | Steam restores these when starting compatibility tools. Armada sets them explicitly to keep the tools' command and library search paths available. | Small launcher change worth testing. Our direct ARM client launch sets neither; use our own runtime paths rather than copying Armada's paths. |
| Proton-CachyOS DXVK probe | Requires `storageBuffer8BitAccess` as well as `descriptorIndexing` before choosing modern DXVK; otherwise allows the bundled fallback. | Low priority on the Nova: our Mesa enables 8-bit storage for A7xx, so this should not change its choice. The guarded patcher works on the real `11.0-20261005-slr` Proton script; its missing/duplicate-probe tests pass. Our installer downloads changing Proton releases, so any adoption must detect the installed script rather than assume that release's shape forever. |

Sources: [GPU priorities](https://github.com/armada-os/armada/blob/4c945ec5b28176c8580059a1c5ab6176ac5f3104/packages/kernel/patches/0619-drm-msm-map-submitqueue-priority-onto-high-low.patch),
[Gamescope patch ledger](https://github.com/armada-os/armada/blob/4c945ec5b28176c8580059a1c5ab6176ac5f3104/packages/gamescope/PATCHES.md),
[Steam launcher](https://github.com/armada-os/armada/blob/4c945ec5b28176c8580059a1c5ab6176ac5f3104/system_files/usr/libexec/armada/launch-steam),
[DXVK probe patcher](https://github.com/armada-os/armada/blob/4c945ec5b28176c8580059a1c5ab6176ac5f3104/packages/proton-cachyos/patch-proton-cachyos-dxvk-probe.py).

### Useful designs requiring adaptation

- **Per-game FEX profiles.** `armada-game-launch` writes `FEX_APP_CONFIG`
  into the user's cache, which pressure-vessel shares with the game. It
  omits `RootFS`, `ThunkHostLibs` and `ThunkGuestLibs`, allowing each
  compatibility tool's FEX to use its own paths. Our system FEX settings
  alone cannot be assumed to configure a bundled FEX. Worth adapting for
  per-game compatibility, with an actual game launch confirming consumption.
- **Controller recovery.** The same wrapper injects missing x86 Wayland
  and xkbcommon libraries into applicable x86 Proton tools, and repairs
  stale Valve-controller registry entries left when changing Proton
  architectures. These are specific workarounds, involving installed tools
  and prefixes: reproduce the missing-library or stale-registry failure
  before adopting either. They do not calibrate the Nova's physical sticks.
- **Steam repair.** `armada_steam.py` stages and verifies replacement client
  files while preserving games, account data and compatibility tools. Its
  Linux tests pass (13 passed, two integration cases skipped). Our installer
  instead removes a real Steam directory when replacing it with the library
  symlink. Adapting preservation and staging is worthwhile; Armada's factory
  payload/OSTree exporter cannot be copied into PortareOS unchanged.

### Leave out for now

- Gamescope `0028` is the three-commit frame-pacing series from
  [Valve PR 2417](https://github.com/ValveSoftware/gamescope/pull/2417),
  merged on 11 October. Our 14 October Gamescope pin already has the
  scheduling helpers, independent nested refresh clocks and Wayland wakeup.
- `0027` changes the **fixed-refresh** limiter. Our normal Steam launch
  uses VRR and its separate limiter; our newer fixed-refresh branch also
  differs from the one Armada patches. Revisit for a measured fixed-refresh
  problem, including external displays.
- `0026` makes Steam's **FSR** selection run **SGSR** on supported SDR
  inputs. Our Gamescope already offers SGSR explicitly. It is a selection
  policy change, with no Nova quality or performance comparison yet.
- The synthetic EDID, nominal Nova HDR profile and hardware color-management
  stack (`0002` through `0006`, `0017`, `0019`, `0021`) are a separate display
  project. Armada's Nova profile explicitly uses unmeasured nominal P3
  primaries; the LUT patches require its kernel's 3D LUT/colorop interfaces,
  which ours does not expose. Do not treat these as a small Steam fix.
- DRM leases, companion-screen MangoApp fixes and the generic fallback
  splash app ID serve Armada's multi-screen/session design. We have one
  screen and already carry a targeted Steam-bootstrap focus fix.
- Gamescope already requests realtime Vulkan queues when it has
  `CAP_SYS_NICE`. Check that capability on our root-run Steam path before
  considering Armada's bypass; it is separate from the kernel's submitqueue
  mapping fix.

The applicability checks used a fresh archive of our exact Gamescope pin
with all five of our patches applied first. `0018`, `0024` and `0025` were
then applied together and reverse-checked in that temporary tree. The
libliftoff tests ran in an ARM64 Debian container against the pinned
dependency, using a fresh build after applying the allocator fix. These
checks establish applicability and regression behavior, not game performance.

## Suspend and sleep power

armada's commit 431bf57 reports Nova sleep power on USB input falling
from 0.67 W to 0.27 W with the following together. The MCU rail above
is one part; the rest is open here and relevant to the overnight drain
item (#62).

This section records the September survey. The PCIe and audio sleep work
was subsequently incorporated in #658; see [power measurements](POWER.md)
for the implementation and remaining device checks.

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
  1024 against post-resume crackle; that part conflicts with our low-latency
  graph, now configured with a 3 ms minimum rather than the earlier
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
  log on every resume, since the kernel keeps only the last wake. Our
  `000-sleep-ledger` post-sleep hook now records the wake IRQ, or a
  wakeup-source fallback, alongside sleep counters and battery charge.
- **Sleep tracer** (`armada_sleep_debug.py`, 1391 lines): a per-cycle
  ftrace instance over power, rpm, clk, regulator, interconnect
  `icc_set_bw`, `rpmh_send_msg` (filtered to the sleep and wake sets)
  and UFS events, then a report. Heavy, but the event list is a recipe.
- **Fan supply in suspend**: their powerd sets pwm-fan `pwm1_enable` to
  3, cutting the fan supply at duty 0 and in suspend. We rely on
  `regulator-off-in-suspend` on the fan regulator instead. Probably
  equivalent; worth one measurement.
- Already equivalent at the survey: dwc3 USB autosuspend (our `81-usb-runtime-pm.rules`),
  PCIe L23 skip (our 0215), PCIe suspend OPP (our 1048/1049, since removed by #658), geni UART
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
  headphone sinks too. PortareOS has since removed DisplayPort audio
  (#709); sound stays on the local outputs.
- **Nova firmware**: their rp6 DTS points ADSP, `adsp_dtb`, AW883xx and
  `battmgr.jsn` at files extracted from a Pocket 6 vendor image rather
  than the Odin 2 fallback we used at the survey. PortareOS now ships the
  Nova's own DSP and amplifier firmware in `nova-firmware`; #729 selects
  the vendor-partition ADSP with the Nova's battery profile. The topology
  keeps its `AYN-Odin2-tplg.bin` filename. The blobs are vendor licensed.
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
  **Taken** as patch 1104, 2026-10-09: the Nova connected 9.4 to 9.7 s
  after resume, 8 s of it in that wait, and 1.9 to 3.0 s with it, 12
  of 13 resumes (one quick scan was aborted, 8.5 s). The wait was what
  let 11d find a country: ath12k stops 11d on association, so with a
  fast reconnect the chip stayed on world rules, without 6 GHz. The
  country now comes from the timezone (`setregdomain`, with
  `ATH_REG_DYNAMIC_USER_REG_HINTS`), and patch 1106 sends it again when
  the radio starts after the power cycle every suspend is.

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
