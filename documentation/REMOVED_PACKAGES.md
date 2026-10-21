# Packages this fork does not keep

The device serves a fixed list of systems, and the emulator picked for each
one is the README's [systems table](../README.md#systems-and-status). Everything below
was removed because it served a system that is not on that list, duplicated
the default emulator, or supported a runtime the device no longer uses.

This was `.upstream-ignore`, the list of packages the upstream import tool
was told never to bring back. Neither survives: the fork does not track
upstream and nothing can restore these. The reasons are what is worth
keeping, because they answer "why don't we ship X?".

Two entries on that list were wrong at the time: `nestopia-lr` and
`beetle-saturn-lr` were both in the tree and both shipped, for NES and
Saturn. Both have since been replaced, and have their rows below.

`documentation/PACKAGE_INVENTORY.md` covers the separate question of what was
trimmed out of the image, with sizes.

## Emulators and cores, with a reason of their own

| Removed | Why |
|---|---|
| `uae4arm-lr` | Unused Amiga core; Amiga and the alternative puae cores are outside the retained system list. |
| `aethersx2-sa` | EOL PS2 appimage. armsx2 is the only PS2 emulator this fork ships. |
| `armsx2-sa` | ARMSX2's SDL frontend. Its libretro core, `armsx2-lr`, replaced it, so PS2 runs in RetroArch. Xbox retains standalone xemu. |
| `cemu-sa` | Wii U emulator with no usable 4:3 mode on a 4:3 panel. Removed, and the wiiu system with it. |
| `drastic-sa` | A closed-source Nintendo DS binary. |
| `daedalusx64-sa` | A 32-bit-only N64 emulator we never built. |
| `bigpemu-sa` | A Jaguar emulator behind retroarch's own. |
| `touchhle-sa` | An iOS app emulator. |
| `vita3k-sa` | PS Vita is 960x544, exactly 16:9, so it letterboxes on this panel the way psp does. Removed with its system. |
| `bsnes-lr` | Replaced Snes9x for the SNES in #520 for its accuracy, with patches for the exact NTSC rate, the DSP's 32040 Hz and accurate defaults. A tester measured the cost: severe frame drops in Yoshi's Island's intro with one run-ahead frame, and the battery going with it, for an accuracy difference nobody noticed in play. Snes9x is back with its exact-rate patch; `sufami` stays gone. |
| `beetle-saturn-lr` | Replaced for the Saturn by `ymir-lr`: Ymir is more accurate, and it runs the VDPs and the SCSP on their own threads where Beetle Saturn ran the console on one, which on this device was the difference a tester saw in Grandia. Ymir is also the one Saturn emulator with a GPU renderer in the making. |
| `nestopia-lr` | Replaced for NES, Famicom and FDS by `mesence-lr`, the nesdev community's Mesen. It is more accurate, and the NES is cheap enough that the accuracy costs nothing that matters here. |
| `gpsp-lr` | Unused alternative to `mgba-lr`. GBA, GBA Hacks and GBA Video all use mGBA. |
| `skyemu-sa`, `skyemu-lr`, `nanoboyadvance-sa`, `hatarisa` | Unselected alternatives; the retained systems use the cores in the README. Neither SkyEmu frontend remains in the tree. |
| `sndio` | The only thing that pulled it in was `touchhle-sa`. |
| `vlc` | Its frontend user was EmulationStation, which was also replaced. The launcher is now portarelauncher; media playback uses mpv and PORTAMP. |

## Systems this fork does not keep

Standalone emulators (11):

`amiberry` `azahar-sa` `gzdoom-sa` `heroic` `hypseus-singe` `melonds-sa`
`minivmacsa` `openbor` `pico-8` `supermodel-sa` `yabasanshiro-sa`

Libretro cores (78):

`81-lr` `a5200-lr` `arduous-lr` `atari800-lr` `b2-lr` `beetle-lynx-lr`
`beetle-ngp-lr` `beetle-pce-fast-lr` `beetle-pce-lr` `beetle-pcfx-lr`
`beetle-supergrafx-lr` `beetle-vb-lr` `beetle-wswan-lr` `bk-lr` `bluemsx-lr`
`boom3-lr` `cap32-lr` `crocods-lr` `daphne-lr` `desmume-lr` `dosbox-core-lr`
`dosbox-pure-lr` `easyrpg-lr` `ecwolf-lr` `emuscv-lr` `fake08-lr`
`fceumm-lr` `fmsx-lr` `freechaf-lr` `freeintv-lr` `fuse-lr` `gearcoleco-lr`
`geargrafx-lr` `gearlynx-lr` `gw-lr` `handy-lr` `hatari-lr` `idtech-lr`
`jaxe-lr` `kronos-lr` `mame2003-lr` `melonds-ds-lr` `melonds-lr` `mesen-lr`
`minivmac-lr` `mojozork-lr` `mu-lr` `np2kai-lr` `o2em-lr` `opera-lr`
`panda3ds-lr` `play-lr` `pokemini-lr` `potator-lr` `prboom-lr`
`prosystem-lr` `puae-lr` `puae2021-lr` `px68k-lr` `quasi88-lr` `quicknes-lr`
`race-lr` `same_cdi-lr` `sameduck-lr` `stella-lr` `theodore-lr` `tic80-lr`
`tyrquake-lr` `uzem-lr` `vecx-lr` `vice-lr` `vircon32-lr` `virtualjaguar-lr`
`vitaquake2-lr` `vitaquake3-lr` `wasm4-lr` `xmil-lr` `yabasanshiro-lr`

## Scripts

| Removed | Why |
|---|---|
| `rocknix-fake-suspend` | The state machine for devices without working suspend. The Nova suspends for real and its power key is owned by the SM8550 power-handler. |

## Tools

| Removed | Why |
|---|---|
| `gamepadcalibration` | GPcal, stick and trigger calibration in Python drawn with pyxel, under Tools. The one stick problem found on the Nova was the MCU's deadband, not calibration, and a calibration tool would be a launcher screen writing the same rsinput parameters. One saved before still applies at boot from `/storage/.config/autostart/GPcal.sh`. |
| `pyxel` | GPcal's UI library, and GPcal its only user. Its upstream (github.com/kitao) disappeared on 2026-10-09 and took the wheel's URL with it. |

## Unused package recipes

These 30 recipes, plus `gpsp-lr` above, were removed from `packages/` with
their patches and support files. None was selected by either the official
or unofficial SM8550 build, including the CI LLVM builds and source-unpack
dependencies. Removing them leaves both build plans unchanged.

| Removed | Why |
|---|---|
| `mako-notify`, `mako-osd` | Require a Wayland compositor; they cannot draw over the launcher's or an emulator's direct KMS output. |
| `bemenu`, `fcft`, `foot`, `sway`, `swaybg`, `tllist`, `waylandpp`, `wl`, `wlr-randr`, `wlroots` | The former Sway desktop and its unused dependencies. Gamescope keeps its Wayland dependencies and bundled wlroots. |
| `at-spi2-atk`, `at-spi2-core`, `atk`, `gdk-pixbuf`, `gtk2`, `gtk3`, `mesa-demos`, `wxwidgets` | Unused GTK frontends, libraries and demos. |
| `common-shaders`, `glsl-shaders`, `retroarch-overlays`, `retropie-shaders` | Already excluded from the image; RetroArch uses the retained `slang-shaders` package. |
| `batteryplus`, `btop`, `entware`, `texturecache.py`, `wait-time-sync` | Legacy tools with no build-plan users. |
| `vulkan-wsi-layer` | Unused Vulkan WSI layer; Mesa supplies the device's Vulkan drivers. |
