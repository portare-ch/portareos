# PortareOS modelines: what is done and what is open

The Nova's panel runs at 119.880 Hz, twice NTSC's 59.94 Hz. Systems with a different native rate get a panel mode at exactly twice their rate, switched on when the game starts. [REFRESH_RATES.md](PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md) has the mechanism and the tables; [CONSOLE_CLOCKS.md](CONSOLE_CLOCKS.md) derives every rate. This page is only the status.

The rate that matters is the one the emulator reports, because that is what RetroArch syncs to. Where it differs from the console's, the column says so. How RetroArch holds the core to the mode, one timed present a frame, is the pacing section of REFRESH_RATES.md.

| System (emulator) | Emulator's rate (Hz) | Panel mode (Hz) | Status |
|---|---|---|---|
| Game Boy, Game Boy Color (Gambatte) | 59.7275 | 119.455 | done |
| Game Boy Advance (mGBA) | 59.7275 | 119.455 | done |
| SNES, Satellaview, MSU-1 (snes9x) | 60.0988 | 120.198 | done |
| NES, Famicom, Famicom Disk System (MesenCE) | 60.0988 | 120.198 | done, shares the SNES mode |
| PlayStation (SwanStation) | 59.826 (patched; upstream 59.8173) | 119.652 | done, shares the N64 mode; 480i runs on it too (0.19 % slow), accepted |
| Saturn (Ymir) | 59.8261 (patched; the wrapper said 59.82) | 119.652 | done, shares the PS1/N64 mode |
| Nintendo 64 (ParaLLEl N64) | 59.826 in 240p, 59.94 in 480i | 119.652 | 240p in #307; 480i runs on the 240p mode (0.19 % slow), accepted |
| Master System, Game Gear, Mega Drive, Mega CD (Genesis Plus GX) | 59.9227 | 119.846 | done |
| 32X (PicoDrive) | 60 (console: 59.9227) | – | open: PicoDrive reports a flat 60, so it needs a core fix before a mode makes sense |
| Neo Geo (FBNeo) | 59.18 (the board's 59.1856, kept in hundredths) | 118.360 | done |
| Neo Geo CD (NeoCD) | 59.5999 | 119.200 | done |
| Arcade (FBNeo) | 54 to 61, per board | 119.880 (default) | not planned: the rate varies too much for one mode |
| Dreamcast, NAOMI, Atomiswave (Flycast) | 59.9453 in 480i/VGA, 59.827 in 240p | 119.880 (default) | 480i and VGA: done, the default is 2×; 240p games: open |
| GameCube, Wii (Dolphin) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| PlayStation 2 (ARMSX2) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| Xbox (xemu) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| PSP (PPSSPP) | 59.94 | 119.880 (default) | done, the default is exactly 2× |
| ScummVM, Steam, ports | no fixed rate | 119.880 (default) | not applicable |
| Movies (mpv) | the file's rate | 119.880 (default) | 23.976, 29.97 and 59.94 fps are exact divisions of the default; 24 and 25 fps rely on mpv's audio sync. Not planned |
| Launcher, music, tools, image viewer | – | 119.880 (default) | not applicable |

Adding a mode is four steps, listed at the end of REFRESH_RATES.md.
