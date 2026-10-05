# Console clocks: where the exact refresh rate comes from

[REFRESH_RATES.md](PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md) lists a native rate for every system. This document shows where each number comes from, so it can be checked, and so the next system can be worked out the same way.

A rate such as 59.94 is not a property of "NTSC". It is the result of a clock chain that is different on every console:

```
frame rate = video clock / (clocks per line × lines per frame)
```

with the video clock itself made from the console's crystal by a PLL or a divider. The often quoted 4.5 MHz / 286 = 15734.266 Hz line, and 59.94 Hz from it, is the broadcast standard for a 525-line interlaced signal. It is only right for a console that outputs exactly that signal. A console that draws a progressive 240p picture, or has its own idea of a line, has its own rate, and a handheld has no broadcast standard to follow at all.

Audio works the same way. A sample rate is a divided clock (the PS1's 44100 Hz is 33.8688 MHz / 768, the N64's is the video clock divided by a register), not a ratio of the frame rate, and a ratio of the two can only be an estimate.

## The NTSC line, and the 263-line rule

NTSC's color subcarrier is 315/88 MHz = 3.579545… MHz. A line is 227.5 subcarrier periods, 15734.266 Hz, and a frame is 525 lines in two interlaced fields of 262.5 lines: 59.9401 fields per second.

Consoles that build their video clock from the subcarrier keep this line. For interlaced output (480i) they use 262.5 lines per field and get 59.940 Hz. For progressive output (240p) a field has to be a whole number of lines, and the PlayStation, the Nintendo 64 and the Dreamcast all use 263: 15734.266 / 263 = **59.826 Hz**. That is why three unrelated consoles share a rate, and why 240p and 480i games on the same console differ.

The SNES and the Sega consoles also derive their clocks from the subcarrier, but their lines are not the standard length (SNES: 0.07 % short; Sega: 0.22 % long), and they use 262 lines, so they have rates of their own.

## Summary

| System | Crystal / master clock | Video clock | Clocks per line | Lines per frame | Native rate (Hz) | Emulator reports (Hz) |
|---|---|---|---|---|---|---|
| Game Boy, Game Boy Color | 4.194304 MHz (2^22) | same | 456 dots | 154 | 59.7275 | 59.7275 (Gambatte) |
| Game Boy Advance | 16.777216 MHz (2^24) | same | 1232 | 228 | 59.7275 | 59.7275 (mGBA) |
| NES, Famicom | 21.477272 MHz (6 × subcarrier) | same | 1364 (341 dots of 4; one dot skipped every other frame) | 262 | 60.0988 | 60.098814 (MesenCE with PortareOS's patch; upstream rounds the master clock to 21477272 Hz, 60.098812) |
| SNES | 21.477272 MHz (6 × subcarrier) | same | 1364 (1360 once every other frame) | 262 | 60.0988 | 60.098814 (bsnes with PortareOS's patch; upstream rounds the master clock to 21477272 and reports 0.034 ppm low) |
| Master System, Game Gear, Mega Drive, Mega CD, 32X | 53.693175 MHz (15 × subcarrier) | same | 3420 | 262 | 59.9227 | 59.9227 (Genesis Plus GX); 60 (PicoDrive) |
| PlayStation | 33.8688 MHz (768 × 44100) | 53.693175 MHz (× 715909/451584) | 3412.5 | 263 (240p), 262.5 (480i) | 59.826, 59.940 | 59.826 for both (SwanStation with PortareOS's patch; upstream 59.8173) |
| Saturn | 28.636364 MHz (8 × subcarrier), or × 61/65 = 26.874126 MHz in the 320-wide modes | same | 1820 dots, or 1708 (both the broadcast line) | 263 (240p), 262.5 (480i) | 59.826, 59.940 | 59.8261 (Beetle Saturn with PortareOS's patch; upstream 59.8265) |
| Nintendo 64 | 14.318182 MHz (4 × subcarrier) | 48.681818 MHz (× 17/5) | 3094 | 263 (240p), 262.5 (480i) | 59.826, 59.940 | 59.826 / 59.94 (ParaLLEl N64 with our patch) |
| Neo Geo MVS | 24.000 MHz | 6.000 MHz (÷ 4) | 384 pixels | 264 | 59.1856 | 59.18 (FBNeo keeps hundredths) |
| Neo Geo AES, Neo Geo CD | 24.167829 MHz | 6.041957 MHz (÷ 4) | 384 pixels | 264 | 59.599 | 59.5999 (NeoCD); FBNeo runs cartridges at the MVS rate |
| Dreamcast, NAOMI, Atomiswave | 27 MHz video clock | 13.5 MHz (÷ 2), 27 MHz for VGA | 858 | 263 (240p), 525 half-lines (480i) | 59.826, 59.940 | 59.827 / 59.9453 (Flycast) |
| GameCube, Wii | 27 MHz video clock (54 MHz progressive) | same | 858 (2 × 429) | 525 half-lines per field | 59.940 | 59.94 (Dolphin) |
| PlayStation 2 | GS CRTC on the standard line | – | – | 525 (480i), 263 (240p) | 59.940, 59.82 | 59.94 always (PCSX2/ARMSX2 vsync timer) |
| PSP | – | – | – | 286 lines | about 59.94 | 60/1.001 (PPSSPP's assumption) |
| Xbox | TV encoder, standard 525-line output | – | – | 525 | 59.940 | 59.94 |

The panel modes in REFRESH_RATES.md follow the **emulator's** column, not the console's: RetroArch syncs audio and video to the rate the core reports. Where the two differ (SwanStation), the emulator is the one to fix before the mode.

## Each console

### Game Boy and Game Boy Color

The CPU crystal is 4.194304 MHz (2^22). The PPU draws a line in 456 dots and a frame in 154 lines (144 visible, 10 VBlank): 456 × 154 = 70224 dots, and 4194304 / 70224 = **59.7275 Hz**. The Game Boy Color doubles the CPU clock in its fast mode but not the PPU's, so the rate does not change.

The APU has no sample rate: its channels are mixed as analog signals.

- Pan Docs, *Rendering* — 456 dots per line, 154 lines, "One frame: 70224 dots @ 59.7 fps": https://gbdev.io/pandocs/Rendering.html
- Gambatte, `libgambatte/libretro/libretro.cpp`: `#define VIDEO_REFRESH_RATE (4194304.0 / 70224.0)`

### Game Boy Advance

The clock is 16.777216 MHz (2^24). A line is 1232 cycles (308 dots × 4), a frame 228 lines (160 visible, 68 VBlank): 280896 cycles, 16777216 / 280896 = **59.7275 Hz**. That is exactly the Game Boy's rate, because 280896 = 4 × 70224 and the clock is 4 × 2^22.

The sound DACs are driven by a timer; the game chooses the rate (commonly 16384 to 32768 Hz, up to 262144).

- GBATEK, *LCD Dimensions and Timings* — "1232 cycles" per line, "280896 cycles - ca. 59.737 Hz": https://problemkaputt.de/gbatek-lcd-dimensions-and-timings.htm
- mGBA, `src/platform/libretro/libretro.c`: `info->timing.fps = core->frequency(core) / core->frameCycles(core)`

### NES and Famicom

The master clock is the SNES's, 21.477272 MHz = 6 × the subcarrier, and the PPU's dot clock is a quarter of it. A line is 341 dots, a frame 262 lines, and with rendering on, the pre-render line of every other frame is one dot short. So a frame averages 341 × 262 × 4 − 2 = 357366 master clocks, exactly the SNES's count, and the rate is the same **60.0988 Hz** (21477272 / 357366). PAL: 26.601712 MHz, 5 clocks per dot, 312 lines, 50.0070 Hz.

Audio: the APU's channels are mixed as analog signals; there is no sample rate. MesenCE mixes at the APU clock into 96000 Hz, then lowpasses and resamples to 32000 Hz (our patch; upstream reports 44100).

- NESdev wiki, *Cycle reference chart* — "21.477272 MHz ± 40 Hz", 4 master clocks per dot, "341 × 262 = 89342" dots, "pre-render line is one dot shorter in every odd frame", "60.0988 Hz": https://www.nesdev.org/wiki/Cycle_reference_chart
- MesenCE, `Core/NES/NesConsole.cpp`, `NesConsole::GetFps`: `60.0988118623484` for NTSC, 21477272 / 357366, which `Libretro/libretro.cpp` reports as `timing.fps`. PortareOS's `003-exact-ntsc-rate.patch` returns `945000000.0 / 44.0 / 357366.0`

### SNES

The master clock is 945/44 MHz = 21.477272 MHz, six times the NTSC subcarrier. A line is 1364 master clocks (341 dots of 4 clocks): 15745.8 Hz, 0.07 % above the broadcast line. A frame is 262 lines. With interlace off, line 240 of every other frame is 4 clocks short (1360), so the average frame is 1364 × 262 − 2 = 357366 clocks, and 21477272 / 357366 = **60.0988 Hz**. PAL: 21.281370 MHz, 312 lines, 50.007 Hz.

Audio: the S-DSP runs from its own 24.576 MHz ceramic resonator and outputs a sample every 768 clocks, 32000 Hz by specification. Real units measure about 32040 Hz, because the resonator is a little fast, and bsnes uses 32040.

- SNESdev wiki, *Timing* — master clock "945/44 MHz ≈ 21.4773 MHz (6 times chroma)", "1364 master clocks = 341 dot cycles", short scanline 1360, "S-DSP clock: 24.576MHz", "DAC samplerate: 32000 Hz by specification (÷(24×32))": https://snes.nesdev.org/wiki/Timing
- bsnes, `bsnes/target-libretro/libretro.cpp`: `info->timing.fps = 21477272.0 / 357366.0` for NTSC, `21281370.0 / 425568.0` for PAL; `bsnes/sfc/system/system.hpp`: `cpuFrequency = Colorburst::NTSC * 6.0`, the exact clock the emulation runs at, and `apuFrequency = 32040.0 * 768.0`. PortareOS reports the NTSC rate from that clock (`001-exact-ntsc-rate.patch`); the rounded constant is 0.034 ppm low, which is the difference between the 120.198 mode being exact and being a near miss. PAL's 21281370 is already exact.

### Master System, Game Gear, Mega Drive, Mega CD, 32X

The master clock is 53.693175 MHz, fifteen times the subcarrier (the Master System's own crystal is a third of that, 10.738635 MHz, with the same result). The VDP's line is 3420 master clocks (342 dots × 10) in both its 256- and 320-pixel modes: 15699.8 Hz, 0.22 % below the broadcast line. A frame is 262 lines: 53693175 / (3420 × 262) = **59.9227 Hz**. PAL: 53.203424 MHz, 313 lines, 49.70 Hz.

Audio: the YM2612 is clocked at master / 7 = 7.670454 MHz and produces a sample every 144 clocks: 53267 Hz. The SN76489 runs at master / 15 = 3.579545 MHz. The Mega CD's RF5C164 samples at 32552 Hz, its CD audio at 44100 Hz. The 32X's PWM rate is set by the game.

Genesis Plus GX computes the rate from these constants. PicoDrive, which we use for the 32X, reports a flat 60 Hz.

- Genesis Plus GX, `core/system.h`: `#define MCLOCK_NTSC 53693175`, `#define MCYCLES_PER_LINE 3420`; `libretro/libretro.c`: `info->timing.fps = system_clock / lines_per_frame / MCYCLES_PER_LINE`, `lines_per_frame = vdp_pal ? 313 : 262`; `core/sound/sound.c`: "YM2612 internal clock = input clock / 6 = (master clock / 7) / 6"
- PicoDrive, `platform/libretro/libretro.c`: `info->timing.fps = Pico.m.pal ? 50 : 60`

### PlayStation

The crystal is 33.8688 MHz = 768 × 44100, chosen for the CD's sample rate; it clocks the CPU and the SPU. The GPU clock is a PLL from it: 33868800 × 715909 / 451584 = 53.693175 MHz, again fifteen times the subcarrier. A line is the broadcast line, 3412.5 GPU clocks (the GPU alternates 3412 and 3413). A 240p frame is 263 lines: 53693175 / (3412.5 × 263) = **59.826 Hz**; 480i is 262.5 lines per field: 59.940 Hz. PAL: 53.203425 MHz, 3406 clocks, 314 lines, 49.76 Hz.

Upstream SwanStation rounds the line to 3413 clocks, so its rate is 53693175 / (3413 × 263) = **59.8173 Hz**, 0.015 % below the console. PortareOS patches it (`001-ntsc-line-is-3412-5-ticks.patch`) to alternate 3413 and 3412 like the console, and Mednafen, which gives 59.826 Hz and lets the PS1 share the N64's panel mode. SwanStation keeps 263 lines for 480i too (the console has 262.5), so 480i games run at 59.826 instead of 59.940.

Audio: the SPU's rate is the crystal / 768 = 44100 Hz exactly.

- psx-spx, *GPU Timings* — "NTSC video clock = 53.693175 MHz", "263 scanlines per field for NTSC non-interlaced", "3413 video cycles per scanline", "Non-interlaced: 59.826 Hz", "Interlaced: 59.940 Hz": https://psx-spx.consoledev.net/graphicsprocessingunitgpu/#gpu-timings
- Mednafen (Beetle PSX), `mednafen/psx/gpu.c`: `GPU.LineClockCounter = 3412 + GPU.PhaseChange - 200; … GPU.PhaseChange = !GPU.PhaseChange;`
- PortareOS, `packages/emulators/libretro/swanstation-lr/patches/001-ntsc-line-is-3412-5-ticks.patch`
- SwanStation, `src/core/system.h`: `MASTER_CLOCK = 44100 * 0x300; // 33868800Hz`; `src/core/gpu.h`: `NTSC_TICKS_PER_LINE = 3413, … NTSC_TOTAL_LINES = 263, PAL_TICKS_PER_LINE = 3406, … PAL_TOTAL_LINES = 314`; `src/core/gpu.cpp`, `SystemTicksToCRTCTicks`: × 715909 / 451584 (NTSC), × 709379 / 451584 (PAL)

### Saturn

The Saturn has two dot clocks and switches between them with the horizontal resolution: 28.636364 MHz, 8 × the subcarrier, for the 352-wide modes, and 61/65 of it, 26.874126 MHz, for the 320-wide ones. A line is 1820 dots in the first and 1708 in the second, and both come to the broadcast line, 15734.26 Hz. A frame is 263 lines in 240p (VDP2 `TVSTAT` counts 0x107 lines in every NTSC mode): 28636363.6 / (1820 × 263) = **59.826 Hz**, the PlayStation's and the N64's rate; 480i alternates 262- and 263-line fields, 59.940 Hz. PAL: 28.4375 MHz, 313 lines, 49.920 Hz.

Beetle Saturn emulates this chain (a 1746818182 Hz timestamp clock divided by 61 or 65, 455 or 427 counter units of 4 per line, 263 lines) and upstream reports a hard-coded 59.8265, 0.0007 % above it; PortareOS patches it (`beetle-saturn-lr/patches/001-exact-ntsc-rate.patch`) to report the exact chain, 59.826105, so the Saturn shares the PS1/N64 panel mode. MAME's 59.7648 comes from pinning both modes to 26.8466 MHz, which is not what the hardware does. Interlaced games run at the reported 240p rate, as on the PlayStation.

Audio: the SCSP outputs 44100 Hz.

- Beetle Saturn, `mednafen/ss/ss.c`: `MasterClock = PAL ? 1734687500 : 1746818182; /* NTSC: 1746818181.818... */`, `VDP2_StartFrame(espec, cur_clock_div == 61)`; `mednafen/ss/vdp2.c`: `HTimings[2][HPHASE__COUNT] = { { 0x140, 0x15B, 0x1AB }, { 0x160, 0x177, 0x1C7 } }` (427 and 455 units), `VTimings` NTSC total `0x107` (263) in all four modes; `libretro.c`, `retro_get_system_av_info`: the comment deriving 59.826105 and rejecting MAME's 59.764802
- PortareOS, `packages/emulators/libretro/beetle-saturn-lr/patches/001-exact-ntsc-rate.patch`
- Ymir, `libs/ymir-core/include/ymir/sys/clocks.hpp`: `kNTSCClock = 39375000.0 * 8.0 / 11.0` (the 352-mode master clock), and `vdp.cpp` times 455 x 4 clocks a line over 263 lines (240p) - the same chain, 59.826105 Hz. Its own `kNTSCFrameRate` constant is `kNTSCClock / (455 * 525 * 2)` = 59.94, the 525-line broadcast figure, used only by the SDL app's pacing and settings page; the libretro wrapper reported a rounded 59.82. PortareOS's `002-exact-rates.patch` reports the VDP's chain.

### Nintendo 64

The crystal is not the subcarrier but four times it: 14.318182 MHz for NTSC, 17.734475 MHz for PAL, 14.302448 MHz for MPAL. A Macronix MX8350 (MX8330 on some boards) makes the clocks from it: the video clock VCLK = X1 × 17 / 5 = **48.681818 MHz** for NTSC (× 14 / 5 = 49.656530 MHz for PAL), and the TV encoder gets X1 / 4 = the subcarrier on its SCIN pin. A pixel is 4 VCLKs, so the pixel clock is 12.17 MHz and a line has 773.5 pixels.

The VI registers give the line and the frame. `VI_H_SYNC` holds the line length in quarter pixels, i.e. in VCLKs: NTSC 0xC15 = 3093, so a line is 3094 VCLKs = 227.5 × 13.6, exactly the broadcast line (48681818 / 3094 = 15734.264 Hz). `VI_V_SYNC` holds the number of half-lines less one: NTSC non-interlaced 0x20D = 525, so 526 half-lines = 263 lines; interlaced 0x20C = 524, 525 half-lines = 262.5 lines. So:

- 240p: 48681818 / (3094 × 263) = **59.826 Hz** (awe444's formula, 2 × 4500000 / (286 × 526), is the same number written in broadcast terms)
- 480i: 48681818 / (3094 × 262.5) = **59.940 Hz**
- PAL: 0xC69 → 3178 VCLKs, 0x271 → 313 lines: 49.920 Hz progressive, 50.000 Hz interlaced

mupen64plus rounds VCLK to 48681812, which changes nothing at this precision. ParaLLEl N64 originally derived the frame period from a nominal 60 Hz and the game's line count; our patch `003-vi-frame-period-from-h-sync.patch` computes it from `VI_H_SYNC` and `VI_V_SYNC` as above, and the 119.6522 Hz panel mode is 2 × 59.826.

Audio: the AI's sample rate is VCLK / (`AI_DACRATE` + 1), so it is whatever divisor the game picks, e.g. 48681818 / 2209 = 22037.9 Hz, never a round number.

- N64brew wiki, *Video DAC* — crystals "NTSC: 14.31818182 MHz, PAL: 17.734475 MHz, MPAL: 14.30244755 MHz", MX8330/MX8350, "VCLK = X1 × Multiplier / 5", 17 for NTSC, "The encoder receives the FSC clock (X1 ÷ 4) via the subcarrier input (SCIN) pin": https://n64brew.dev/wiki/Video_DAC
- N64brew wiki, *Video Interface* — "227.5 chroma periods per scanline. NTSC N64 has 13.6 VI clocks per chroma period. 227.5 × 13.6 = 3094", H_TOTAL 3093 (NTSC) / 3177 (PAL), V_SYNC "non-interlaced: 525, interlaced: 524" (NTSC), 625 / 624 (PAL): https://n64brew.dev/wiki/Video_Interface
- N64brew wiki, *Audio Interface* — the DAC rate register: https://n64brew.dev/wiki/Audio_Interface
- awe444 in *Nintendo 64 De-blur*, videogameperfection.com forums, page 2 — the crystal is 4 × subcarrier, the MX8350 divides it, and 4500/286 kHz only holds for 525i: https://www.videogameperfection.com/forums/topic/nintendo-64-de-blur/page/2/
- mupen64plus-core, `src/device/rcp/vi/vi_controller.c`: `vi_clock_from_tv_standard` returns 49656530 (PAL), 48628316 (MPAL), 48681812 (NTSC)
- PortareOS, `packages/emulators/libretro/parallel-n64-lr/patches/003-vi-frame-period-from-h-sync.patch`

### Neo Geo

The MVS (arcade) board has a 24.000 MHz crystal. The pixel clock is a quarter of it, 6.000 MHz; a line is 384 pixels, 15625 Hz, and a frame 264 lines: 15625 / 264 = **59.1856 Hz**. The AES (home console) has a 24.167829 MHz crystal instead, which puts its line on the broadcast 15734 Hz and its frame at 59.599 Hz. FBNeo runs cartridge games with the MVS timing, but keeps its frame rate as an integer number of hundredths of a hertz, `nBurnFPS = (INT32)(100.0 * dFrameRate)`, so it reports and paces at **59.18 Hz**, not 59.1856; the panel mode matches 59.18. NeoCD, which runs the Neo Geo CD, uses the CD's crystal, rounded to 24.168 MHz and a 6.042 MHz pixel clock: 6042000 / (384 × 264) = **59.5999 Hz**.

Audio: the YM2610 is clocked at 8 MHz and outputs a sample every 144 clocks: 55555.6 Hz.

- NeoGeo Development Wiki, *Framerate* — MVS "24.000000MHz main clock", "6.000000MHz" pixel clock, 384 pixels, 264 lines, "15.625kHz", "59.1856 frames/second"; AES "24.167829MHz", "59.599": https://wiki.neogeodev.org/index.php?title=Framerate
- FBNeo, `src/burn/drv/neogeo/neo_run.cpp`: `#define NEO_HREFRESH (15625.0)`, `#define NEO_VREFRESH (NEO_HREFRESH / 264.0)`, `#define NEO_CDVREFRESH (6041957.0 / (264 * 384))`; `src/burn/burn.cpp`, `BurnSetRefreshRate`: `nBurnFPS = (INT32)(100.0 * dFrameRate)`; `src/burner/libretro/libretro.cpp`: `timing = { nBurnFPS / 100.0, … }`
- NeoCD, `src/timer.h`: `MASTER_CLOCK = 24168000.0`, `PIXEL_CLOCK = 6042000.0`, `SCREEN_WIDTH = 384`, `SCREEN_HEIGHT = 264`, `FRAME_RATE = PIXEL_CLOCK / (SCREEN_WIDTH * SCREEN_HEIGHT)`; `src/burn/drv/neogeo/d_neogeo.cpp`: "vsync: ~59.18 Hz (264 scanlines make up a single frame)"

### Dreamcast, NAOMI, Atomiswave

The video clock is 27 MHz, and the pixel clock is half of it, 13.5 MHz, unless `FB_R_CTRL.vclk_div` selects the full 27 MHz (the 31 kHz VGA modes). The sync generator's `SPG_LOAD` register holds the line length and the frame height less one. The standard modes (KallistiOS's table below) use hcount = 857 (858 clocks, at 13.5 MHz exactly the broadcast line) and vcount = 262 for 240p, 263 lines: 27000000 / 2 / (858 × 263) = **59.826 Hz**. For 480i, vcount = 524 with the interlace bit set: 525 half-lines per field, 59.940 Hz. VGA: 27 MHz, 858 clocks, 525 lines: also 59.940 Hz.

Flycast recomputes its rate every time the game writes `SPG_LOAD`, in SH-4 cycles: the 200 MHz SH-4 clock divided by the line cycles, which it truncates to an integer (12711 rather than 12711.1). So it reports 59.827 Hz for a 240p game and 59.9453 Hz for a 480i or VGA game, and starts with 59.9453 before a game sets anything.

Audio: the AICA's sample rate is 44100 Hz.

- Flycast, `core/hw/pvr/spg.cpp`: `constexpr int PIXEL_CLOCK = 27 * 1000 * 1000`; `CalculateSync()`: `pixel_clock = PIXEL_CLOCK / (FB_R_CTRL.vclk_div ? 1 : 2)`, `pvr_numscanlines = SPG_LOAD.vcount + 1`, `Line_Cycles = SH4_MAIN_CLOCK * (SPG_LOAD.hcount + 1) / pixel_clock`, halved when interlaced, `retro_refresh_av_info(SH4_MAIN_CLOCK / (Line_Cycles * pvr_numscanlines))`; `shell/libretro/libretro.cpp`: `fps = fps_spg ? fps_spg : SPG_CONTROL.isPAL() ? 50.0 : 59.945300`
- KallistiOS, `kernel/arch/dreamcast/hardware/video.c` — the mode table's `scanlines, clocks` columns: `262, 857` for 320×240 NTSC, `524, 857` for 640×480 NTSC interlaced

### GameCube and Wii

The video interface runs from a 27 MHz clock (54 MHz for progressive scan). Its half-line length register `HLW` is 429 samples, so a line is 858 samples of 27 MHz: 63.556 µs, the broadcast line; Dolphin's source states it as 1.001 / (30 × 525). A field is 525 half-lines, so interlaced and progressive both give **59.940 Hz**.

Dolphin derives the rate as 2 × (system clock) / (ticks of the even field + ticks of the odd field), where the ticks per half-line come from `HLW`; for NTSC that is 59.94.

Audio: the DSP outputs 32 kHz (the GameCube's is measured at 32029 Hz); streamed disc audio is 48 kHz.

- Dolphin, `Source/Core/Core/HW/VideoInterface.cpp`: `CLOCK_FREQUENCIES{{ 27000000, 54000000 }}`; "The line is 63.55555..us long, which is derived from 1.001 / (30 * 525)"; `UpdateRefreshRate()`: `m_target_refresh_rate_numerator = GetTicksPerSecond() * 2; m_target_refresh_rate_denominator = GetTicksPerEvenField() + GetTicksPerOddField()`; `GetNominalTicksPerHalfLine() = GetTicksPerSample() * m_h_timing_0.HLW`

### PlayStation 2

The GS's CRTC outputs the standard signal: 480i at 59.94 Hz, and 240p games at 59.82 Hz, in PCSX2's own words. PCSX2 (and ARMSX2, which is built from it) does not derive the rate from the CRTC at all: its vsync comes from a timer fixed at 59.94 Hz for NTSC, "regardless if the GS is outputting interlace or progressive scan content". So the emulator runs every game at **59.94 Hz**, and a 240p game runs 0.2 % faster than on the console.

Audio: the SPU2 outputs 48 kHz.

- PCSX2, `pcsx2/Counters.cpp` — "According to the GS: NTSC (interlaced): 59.94, NTSC (non-interlaced): 59.82, PAL (interlaced): 50.00, PAL (non-interlaced): 49.76"; `UpdateVSyncRate()`: "The PS2's vsync timer is an *independent* crystal that is fixed to either 59.94 (NTSC) or 50.0 (PAL) Hz"; `pcsx2/Config.h`: `DEFAULT_FRAME_RATE_NTSC = 59.94f`

### PSP

PPSSPP times the display as 60 Hz divided by 1.001, "to compensate for the classic 59.94 NTSC framerate that the PSP seems to have", with 286 lines per frame; it reports 60 / 1.001 to RetroArch. We have not found a datasheet-level derivation for the PSP's LCD, so the number in REFRESH_RATES.md is PPSSPP's.

Audio: 44100 Hz.

- PPSSPP, `Core/HLE/sceDisplay.cpp`: "1.001f to compensate for the classic 59.94 NTSC framerate that the PSP seems to have", `timePerVblank = 1.001 / (double)framerate`; `Core/HW/Display.cpp`: `hCountPerVblank = 286`; `libretro/libretro.cpp`: `info->timing.fps = (60.0 / 1.001) / vsyncSwapInterval`

### Xbox

The Xbox's TV encoder outputs the standard 525-line signal, 59.94 Hz interlaced or progressive. We have not traced xemu's own vblank timer in its source; the table uses the hardware figure.

### Arcade (FBNeo)

Every board has its own crystal and line count, and every FBNeo driver sets its rate from them (`BurnSetRefreshRate`); FBNeo reports the driver's rate to RetroArch, and logs it as "Timing set to … Hz". The rates run from about 54 to 61 Hz, so no single panel mode fits, and the default 119.88 Hz mode is used.

- FBNeo, `src/burner/libretro/libretro.cpp`: `timing = { nBurnFPS / 100.0, … }`, "[FBNeo] Timing set to %f Hz"

## Checking a rate on the device

Start the game from a shell with `retroarch -v …` and look for the core's `fps` in the log: RetroArch prints the timing it was given (`[Core]: … fps` in the av_info lines), and several cores log their own (FBNeo's "Timing set to", Flycast's rate on every `SPG_LOAD` write). Then compare with `modetest -c`, which lists the panel modes with their pixel clocks: the mode's rate is clock / (1302 × 1001), and it should be twice the core's number.
