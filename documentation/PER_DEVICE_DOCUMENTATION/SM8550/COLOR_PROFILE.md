# The color profiles: sRGB and D65 on the Nova's panel, at gamma 2.2 or the sRGB curve

Status, 26 September 2026: both profiles crush the dark greys on the device and stock is the default until they are refitted. The section "Known issue" says what is known.

The Nova's panel is wide-gamut and its white is blue-tinted. Shown as they are, sRGB games and films come out oversaturated (red at x = 0.68 where sRGB puts it at 0.64; green at 0.26/0.71 where sRGB has 0.30/0.60) and cool. [pippopapera measured it](https://github.com/pippopapera/nova-display-calibration) with an X-Rite i1Display Pro Plus, 921 readings, and published a correction for Android that brings 36 colors near the gamut boundary from a mean ΔE00 of 5.8 to 0.6. This is our version of that correction for Linux, and the honest account of how far it gets.

**Settings > Color profile** switches between *stock*, *Gamma 2.2* and *sRGB*. **Stock is the default and, for now, the recommendation**: on the device both corrections crush the dark greys, several codes near black coming out as one black (see "Known issue" below), and until they are refitted the uncorrected panel is the better picture. Both corrections aim at sRGB primaries and a D65 white; they differ in the tone curve. Gamma 2.2 is a pure power law, what CRTs did and what CRT-era games were drawn on, and it is the one meant for emulators once it works. sRGB is the piecewise curve of the sRGB standard, with a linear toe that lifts the shadows (code 16 is 0.52 % of white against 0.23 % under gamma 2.2). The setting is `display.colorprofile` in `system.cfg` (`stock`, `gamma22`, `srgb`), the files are `/usr/config/color/gamma22.profile` and `srgb.profile`, and the launcher writes the chosen one into the display controller (portarelauncher `color.c`, `kms.c`). It holds for everything: every emulator, mpv, Steam, the launcher itself.

## Where the correction lives

Not in the games, not in a compositor, in the display controller. Qualcomm's DPU has a post-processing block per layer mixer (the DSPP) with three stages in order:

| stage | what it does | Android profile | mainline `drm/msm` |
|---|---|---|---|
| IGC | a 1D table per channel, 8-bit in → 12-bit linear out: the de-gamma | yes | **not driven** (`DEGAMMA_LUT` size 0) |
| PCC | a 3×3 matrix | yes | CRTC `CTM` |
| GC | a 1D table per channel, 1024 entries, 10-bit: the output curve | yes | CRTC `GAMMA_LUT` |

Mainline (`drivers/gpu/drm/msm/disp/dpu1/dpu_hw_dspp.c`) implements PCC and GC. The IGC on this SoC is version 4, whose table is loaded through the LUTDMA engine rather than by register writes (downstream `reg_dmav2_setup_dspp_igcv4`, `LUTBUS_BLOCK_IGC`), and mainline has no LUTDMA at all. So the linearisation stage the Android profile relies on is out of reach without a real driver project, and the correction has to be built from a matrix on gamma-encoded values followed by an output table.

The DPU applies the two blocks from the CRTC's state on every modeset (`_dpu_crtc_setup_cp_blocks`, called when color management changed or a modeset happened) and reserves a DSPP for the CRTC as soon as `CTM` or `GAMMA_LUT` is set. A later client's modeset duplicates the CRTC state including both blobs, so what the launcher sets once stays in force until something clears it — and something did: Mesa's `VK_KHR_display` backend, which RetroArch's Vulkan driver uses on KMS, adds `GAMMA_LUT = 0`, `DEGAMMA_LUT = 0` and `CTM = 0` to its first modeset, against transforms "left behind by another user". Measured on the device: blobs set with the launcher on screen, empty while a game ran. PortareOS patches that out of Mesa (`packages/graphics/mesa/patches/mesa-002-wsi-display-keep-crtc-color-transforms.patch`), and the launcher writes the profile again every time it takes the panel back. mpv's DRM output does not touch the properties; Steam's gamescope manages the CRTC's color pipeline itself and is on its own.

## How the profile was made

`projects/PortareOS/packages/portareos/sources/color/fit-profile.py`, from a checkout of their repository, once per tone curve (`gamma22`, `srgb`):

1. **A model of the panel.** Their 261 readings at the reference brightness (173/255) were taken through three pipelines: the factory one (39 readings, which we take as the raw panel: mainline applies no correction at all, so this is what PortareOS shows today) and their two profiles (222 readings). Their IGC, PCC and GC tables are published, so for every reading the value the panel was actually driven with is known. An additive display model — three primaries, one tone curve, and a brightness limiter that pulls white 7 % below the sum of the primaries, as measured — is fitted to all 261: median error 0.6 %. Run through it, their gamma 2.2 profile predicts a mean ΔE00 of 0.54 on the 36 boundary colors; they measured 0.63. That is the check that the model can be trusted.
2. **The correction for our pipeline.** A 3×3 matrix and a 22-knot monotone curve per channel, optimised together to minimise CIEDE2000 against sRGB primaries, D65 and the chosen tone curve — their targets and their equations (`tools/color_math.py`) — over the 36 boundary colors, the 56 reference patches, a 6×6×6 grid and a gray ramp, from eight starting points.
3. **The file.** `ctm` and 1024 `lut` lines, the DRM formats, with the predicted numbers in its header.

## What to expect

Predicted by the model, not measured — we have no colorimeter, and the second column is the whole point of writing this down:

Each profile is judged against its own target (gamma 2.2 or the sRGB curve), which is why the stock column differs between the two:

| set | stock → Gamma 2.2 profile | stock → sRGB profile |
|---|---|---|
| 36 gamut-boundary colors | 5.48 → **2.83** | 5.61 → **2.76** |
| 56 reference patches (grays, primaries, mixes, skin) | 5.13 → **3.38** | 5.29 → **3.19** |
| 6×6×6 grid | 4.68 → **2.01** | 4.81 → **1.82** |
| gray ramp, codes 8 to 255 | 3.98 → **1.93** | 4.34 → **1.99** |

Mean ΔE00; the maxima are in each file's header. White is driven at about 96 % of the stock luminance in both.

For comparison, the Android three-stage gamma 2.2 profile predicts 0.54 / 0.71 / 0.64 on the first three sets. The gap is the missing IGC: a matrix applied to gamma-encoded values desaturates a full-intensity color by the right amount and a darker one by too little, and no output table can undo that afterwards. Grays, the white point and the tone curve are exact in this pipeline; the residual is in saturated mid-tones. The darkest grays (codes 16 to 32) are uncertain in every profile, theirs included: the panel's black floor and the model's behaviour there are both poorly known.

White is dimmer with the profile on, as it is on Android (they lost 10 %): a D65 white on a blue-tinted panel means less blue, and the tone curve costs the rest. The brightness slider is untouched.

## Known issue: the dark greys crush

Seen on the device with both profiles, 26 September 2026: the darkest greys collapse, so a gradient that stock shows as distinct steps near black shows as one black with a profile on. The fit's own account already flagged the region: codes 16 to 32 are the least certain part of every profile, theirs included, because the panel's black floor and the model's behaviour there are poorly known. The likely mechanism is that the fitted output table drives the low codes below the level the panel can still distinguish, an OLED's near-black being a step function more than a curve, and what the table means as 0.2 % of white the panel shows as off. The fit minimises ΔE00 over sets that are mostly mid-tones and saturated colors, so an error confined to the bottom few codes costs it almost nothing.

Not ruled out: that the matrix on gamma-encoded values pulls near-black colors, not only greys, under the floor, since a matrix that desaturates by the right amount at full intensity desaturates too little in the darks and the table then compensates in the wrong direction.

The fix is a refit that pins the bottom of the curve: hold codes 0 to 24 at or above stock's levels, or fit a toe that starts at the measured black floor, and check on the device with a 16-step grey ramp before anything else. The three-stage profiles built from pippopapera's own tables (below) are the other route, since their IGC lifts the darks where their measurement says to, and they measured that result. Until one of these is done, stock is the shipped default, and an install that had chosen a profile is moved back to stock once by `post-update` (`colorprofile-stock`).

## Caveats

- **One unit measured, not this one.** Their readings are from their Nova. Panels of one model vary; expect to be close, not exact.
- **Raw panel = Android "original" is an assumption.** Their original readings went through the factory QDCM configuration, whose tables their installer enables (so they were off) but whose picture adjustment we cannot see. The model fits those 39 readings to 0.85 % median together with the rest, which is consistent with the assumption, not a proof.
- **Their spectral correction is a generic OLED CCSS**, marked provisional by them; absolute numbers inherit that.
- **Full-screen patches.** The brightness limiter was measured on full-screen colors; a game's average picture level is lower, so bright saturated areas in a game may sit a little differently.

## The third stage: the IGC through the LUTDMA

Driving the IGC means driving the LUTDMA, and that is what kernel patches `1070-drm-msm-dpu-DSPP-IGC-through-the-LUTDMA-DEGAMMA_LUT.patch` and `1071-arm64-dts-qcom-sm8550-mdss-regdma.patch` do:

- `dpu_hw_reg_dma.c`: the engine, for this one consumer. A page in the display's address space holds the command sequence — select the DSPP, a LUT bus write of the 257-entry table, the IGC's enable register — and a two-dword last command; both are queued on the CTL's queue 0, the CTL's trigger register (`+0xd4`) starts them, and the done bit (`INTR0`, bit 16 for CTL 0) is polled, 20 ms at most. Offsets and encodings are the downstream `sde_hw_reg_dma_v1.c`'s for engine version 2.0 and its `reg_dmav2_setup_dspp_igcv4()`. Only the "DB" block at `0x0aeac000` is used; the "SB" block, which downstream triggers off the DSPP flush, is not needed.
- The catalog gains the IGC block (`0x1260`, v4) and the engine's description; the CTL's DSPP flush learns the IGC's sub-block bit (2); `dpu_crtc.c` turns the CRTC's `DEGAMMA_LUT` (256 entries, 12 bits used) into the table and the enable (`igc.base + 4`, bit 8); the device tree names the engine's registers as `regdma`. Without the region or the engine nothing changes: no `DEGAMMA_LUT`, the IGC untouched.

The measurement that proved the need is in #161: with the enable written through the register path, the bit does not even stick; the block accepts its table over the LUT bus only.

With the stage available, pippopapera's three tables port one to one: `sources/color/make-igc-profile.py` writes `<curve>-igc.profile` with their IGC as `degamma`, their PCC as `ctm` (now on linear light, as they meant it) and their GC as `lut`. portarelauncher 0.2.2 and later load `<key>-igc.profile` when the CRTC has a `DEGAMMA_LUT`, and `<key>.profile` otherwise, so an image carries both and the controller decides. Their measured result for the three-stage gamma 2.2 profile is a mean ΔE00 of 0.63 on the 36 boundary colors.

Until a device has run it: the engine is written from downstream source, not from documentation, and a wrong descriptor is a display hang. The first test is the kernel alone (nothing changes), then a three-stage file bind-mounted over `/usr/config/color/` with SSH open, the profile switched in Settings, and `journalctl -k | grep -i lutdma`.

## Licence

The readings and tables the fit starts from are MIT, Copyright (c) 2026 pippopapera. The profile file and the fit script carry the notice.
