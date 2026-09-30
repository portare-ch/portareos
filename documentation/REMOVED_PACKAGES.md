# Packages this fork does not keep

The device serves a fixed list of systems, and the emulator picked for each
one is the table in the README's "One emulator per system". Everything below
was removed because it served a system that is not on that list, or because
it duplicated the emulator that was already the default.

This was `.upstream-ignore`, the list of packages the upstream import tool
was told never to bring back. Neither survives: the fork does not track
upstream and nothing can restore these. The reasons are what is worth
keeping, because they answer "why don't we ship X?".

Two entries on that list were wrong, and are not below: `nestopia-lr` and
`beetle-saturn-lr` are both in the tree and both shipped, for NES and Saturn.

`documentation/PACKAGE_INVENTORY.md` covers the separate question of what was
trimmed out of the image, with sizes.

## Emulators and cores, with a reason of their own

| Removed | Why |
|---|---|
| `uae4arm-lr` | Amiga core we do not use; puae covers it. |
| `aethersx2-sa` | EOL PS2 appimage. armsx2 is the only PS2 emulator this fork ships. |
| `cemu-sa` | Wii U emulator with no usable 4:3 mode on a 4:3 panel. Removed, and the wiiu system with it. |
| `drastic-sa` | A closed-source Nintendo DS binary. |
| `daedalusx64-sa` | A 32-bit-only N64 emulator we never built. |
| `bigpemu-sa` | A Jaguar emulator behind retroarch's own. |
| `touchhle-sa` | An iOS app emulator. |
| `vita3k-sa` | PS Vita is 960x544, exactly 16:9, so it letterboxes on this panel the way psp does. Removed with its system. |
| `skyemu-sa`, `nanoboyadvance-sa`, `hatarisa` | Alternatives nobody defaulted to, all covered by the retroarch core that was already the default. skyemu also remains as `skyemu-lr`. |
| `sndio` | The only thing that pulled it in was `touchhle-sa`. |
| `vlc` | Only emulationstation ever linked it, and that is libmpv now. |

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
