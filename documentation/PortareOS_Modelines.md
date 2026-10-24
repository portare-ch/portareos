# PortareOS modelines: what is done and what is open

RetroArch, the launcher and Steam default to variable refresh on the Nova's
fastest 120.198 Hz mode, within a 65–120.198 Hz range. The console rows below
describe the **fixed-refresh fallback**, used by RetroArch when VRR is
disabled and by mpv. Its preferred mode is 119.880 Hz, approximately twice
NTSC's 59.94 Hz. [REFRESH_RATES.md](PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md)
has the mechanism and tables; [CONSOLE_CLOCKS.md](CONSOLE_CLOCKS.md) derives
the rates.

The rate that matters is the one the emulator reports, because RetroArch's
Sync to Exact Content Framerate paces the core at that rate even with fixed
refresh. Where it differs from the console's, the column says so. Vsync and
BFI have been removed. Current presentation is described in
[variable refresh](VARIABLE_REFRESH.md#the-launch).

| System (emulator) | Emulator's rate (Hz) | Panel mode (Hz) | Status |
|---|---|---|---|
| Game Boy, Game Boy Color (Gambatte) | 59.7275 | 119.455 | done |
| Game Boy Advance (mGBA) | 59.7275 | 119.455 | done |
| SNES, Satellaview, MSU-1 (snes9x) | 60.0988 | 120.198 | done |
| NES, Famicom, Famicom Disk System (MesenCE) | 60.0988 | 120.198 | done, shares the SNES mode |
| PlayStation (SwanStation) | 59.826 (patched; upstream 59.8173) | 119.652 | done, shares the N64 mode; 480i runs on it too (0.19 % slow), accepted |
| Saturn (Ymir) | 59.8261 (patched; the wrapper said 59.82) | 119.652 | done, shares the PS1/N64 mode |
| Nintendo 64 (ParaLLEl N64) | 59.826 in 240p, 59.94 in 480i | 119.652 | 240p in #307; fixed refresh retains the 240p mode for 480i, while the core timer runs at 59.94 Hz |
| Master System, Game Gear, Mega Drive, Mega CD (Genesis Plus GX) | 59.9227 | 119.846 | done |
| 32X (PicoDrive) | 60 (console: 59.9227) | – | open: PicoDrive reports a flat 60, so it needs a core fix before a mode makes sense |
| Neo Geo (FBNeo) | 59.18 (the board's 59.1856, kept in hundredths) | 118.360 | done |
| Neo Geo CD (NeoCD) | 59.5999 | 119.200 | done |
| Arcade (FBNeo) | 54 to 61, per board | 119.880 (default) | not planned: the rate varies too much for one mode |
| Dreamcast, NAOMI, Atomiswave (Flycast) | 59.9453 in 480i/VGA, 59.827 in 240p | 119.880 (default) | 480i and VGA: near 2× the reported rate; 240p games: open |
| GameCube, Wii (Dolphin) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| PlayStation 2 (ARMSX2) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| Xbox (hakuX) | 59.94 | 119.880 (default) | done: the core runs on RetroArch's VRR path at exactly 60000/1001 Hz |
| PSP (PPSSPP) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| ScummVM, ports | no fixed rate | 119.880 (default) | no dedicated fixed mode |
| Steam | capped at 60 fps | 120.198 with VRR | gamescope; real-game validation on the final stack pending |
| Movies (mpv) | the file's rate | 119.880 (default) | 23.976, 29.97 and 59.94 fps are exact divisions of the default; 24 and 25 fps rely on mpv's audio sync. Not planned |
| Launcher | 60 flips/s on the built-in panel | 120.198 with VRR | measured repeat cadence; see VARIABLE_REFRESH.md |
| Music, tools, image viewer | – | application-dependent | no dedicated console mode |

Adding a mode is four steps, listed at the end of REFRESH_RATES.md.
