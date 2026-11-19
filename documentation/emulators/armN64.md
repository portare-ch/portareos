# armN64

## What runs

`armn64-lr` builds armN64 1.4 (`b071663e581fb59ce1cd8dff67658efd71ed37bf`)
from [MagnominusGit/armN64](https://github.com/MagnominusGit/armN64), as
`armn64_libretro.so`. The standalone app is not built. It replaces
ParaLLEl N64 as the only Nintendo 64 core.

## Presentation and settings

The default is Vulkan at 2× resolution, Fast (`hle`) accuracy, no overclock
and no frame skipping. This is armN64's fast renderer, not ParaLLEl-RDP or
armN64's exact renderer. Fixed resolution scaling counts from 320×240;
2× therefore targets roughly 640×480, including high-resolution games.
The CPU renderer offers exact native-resolution drawing as an alternative.

System or per-game settings in `system.cfg` use `armn64_renderer`,
`armn64_resolution`, `armn64_accuracy` and `armn64_controller_pak`. For
example, `n64.armn64_renderer=cpu` selects software rendering. The defaults
also live in RetroArch's global core-options file. Run-ahead stays off
until its Vulkan path is tested on the Nova.

## Pacing

Patch `001-native-video-and-audio-timing.patch` replaces the fixed 60/50 Hz
field period and frontend rate with the VI register calculation used by
PortareOS's previous core:

    fps = VI_clock × 2 / ((V_SYNC + 1) × (H_SYNC + 1))

The VI clock is 48,681,812 Hz for NTSC, 49,656,530 Hz for PAL and
48,628,316 Hz for MPAL. Before the game programs the registers, the region's
standard timing is used. Register changes take effect at a field boundary;
RetroArch receives an AV update when the reported frame rate changes.
The emulated CPU field length follows the same period. CPU overclocking
changes cycles per field, not the VI clock.

The fixed-refresh setting retains the 119.6522 Hz panel request for NTSC
240p. Variable refresh follows the core's reported rate as before.

## Audio

The same patch removes armN64's internal linear resampler to 44.1 kHz.
The original stereo AI samples reach RetroArch unchanged, with the rate
reported as `VI_clock / (AI_DACRATE + 1)`. The initial rate is 32,040 Hz
until the game programs the DAC. An AV update reports a changed rate
before its audio is submitted, including changes during play and resets.

`audio_out_rate=0` remains automatic: RetroArch's existing rate-selection
patch chooses the Nova's 32, 44.1 or 48 kHz link and reopens audio when
needed. Thus a roughly 22 kHz game uses 44.1 kHz, and a roughly 32 kHz game
uses 32 kHz. RetroArch performs the resampling to the supported link rate;
the core no longer adds a separate conversion first.

## Existing installs

The update adds the new core defaults and the `config/armN64/` override.
Saved N64 system and per-game selections of `parallel_n64` are changed to
`armn64`. Old core options and overrides are retained but are not used by
the new core.

Cartridge `.srm` saves use the same 0x48800-byte layout as ParaLLEl N64:
EEPROM, four Controller Paks, SRAM and FlashRAM. The existing save path
does not change. Save states belong to the old emulator and cannot be
loaded in armN64. 64DD needs `64DD_IPL.bin` in RetroArch's system directory;
its disk writes use armN64's `<disk name>.ndd.sav` format, and old disk
save data is not converted.

## Verification

Build the patched source with Vulkan enabled, then run the headless AV
test. `src` below is the unpacked source after applying the package patch:

```sh
cmake -S "$src" -B "$build" -G Ninja \
  -DARMN64_TUNE=OFF -DARMN64_APP=OFF -DARMN64_VULKAN=ON
cmake --build "$build" --target armn64_libretro
cmake -S packages/emulators/libretro/armn64-lr/tests -B "$tests" -G Ninja \
  -DARMN64_SOURCE="$src" -DARMN64_BUILD="$build"
cmake --build "$tests"
ctest --test-dir "$tests" --output-on-failure
```

The generated idle ROM needs no game files. Tests cover native samples,
DAC changes, NTSC/PAL/MPAL timing, independent H_SYNC changes, overclocking
and reset. The unpatched frontend fails the frame-rate assertion.

## Open questions

The complete Nova image, Vulkan presentation, game compatibility, save
continuity, audio-link transitions and guide handover still need device
testing. Existing ParaLLEl N64 performance and latency measurements do not
describe armN64.
