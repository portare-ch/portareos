# Refresh and audio rates on the Retroid Pocket Nova (SM8550)

The panel has no variable refresh rate. It runs at **119.880120 Hz**, twice NTSC's 59.94 Hz. For systems whose native rate is noticeably different, `setsettings.sh` (`set_ra_refresh_rate`) asks for a panel mode at exactly twice that rate, and RetroArch switches to it when the game starts.

Where each system's native rate comes from, crystal by crystal, and where an emulator's number differs from the console's, is derived in [CONSOLE_CLOCKS.md](../../CONSOLE_CLOCKS.md). Which systems have their mode, and which are still open, is in [PortareOS_Modelines.md](../../PortareOS_Modelines.md).

The console modes use the same 1302 × 1001 total timings and change only the pixel clock. Steam's 120.000 Hz mode keeps the default's pixel clock and has one line fewer, 1302 × 1000, which was set from userspace and measured before it was added: 120.003 Hz over a minute of vblanks, against 119.884 for the default on the same count. Nothing else picks it: RetroArch asks for each system's exact rate, and mpv, ARMSX2, xemu and the launcher take the preferred mode. All of them keep the panel in its 120 Hz class. The modes are defined in the panel driver, `projects/PortareOS/devices/SM8550/patches/linux/0105-drm-panel-Add-Retroid-Pocket-Nova-panel.patch`.

| Panel mode | Pixel clock | Used by |
|---|---|---|
| 119.880120 Hz | 156240 kHz | default (launcher, everything else) |
| 119.455046 Hz | 155686 kHz | `gambatte`, `mgba` |
| 120.197628 Hz | 174651 kHz, vtotal 1116 | `snes9x`, `nestopia` - exact, and the wide-blanking mode; see below |
| 119.652237 Hz | 155943 kHz | `parallel_n64`, `swanstation`, `mednafen_saturn` |
| 119.845592 Hz | 156195 kHz | `genesis_plus_gx` |
| 118.360134 Hz | 154259 kHz | `fbneo`, for `neogeo` only |
| 119.199541 Hz | 155353 kHz | `neocd` |
| 120.000000 Hz | 156240 kHz, vtotal 1000 | gamescope, for Steam |

### Why one mode has a taller vertical total

Every mode here carries 27 lines of vertical back porch except the SNES
one, which carries 67. Black frame insertion flips on every refresh
rather than every second one, so it meets the vertical blanking deadline
twice as often, and the DPU starts fetching the next frame inside that
window. At 27 lines the window is 340.8us and, measured on snes9x with
BFI, about three flips in 10,800 missed it over 90 seconds. A missed
flip inverts the light/dark alternation, which shows as a black band
rolling down the panel.

156 lines gives 1163.0us, 3.41x the margin. It is also the one mode in
the table that is exact: 174651000 / (1302 x 1116) is 120.197628, which
is 2 x 60.0988 to the six figures a whole-kHz pixel clock can express,
so the frontend has no correction to make and the cadence does not drift
- a frame every 823 hours against every two.

That holds only while both cores report the clock exactly. Nestopia
does. Snes9x rounds the master clock to 21477272 and comes out 0.034 ppm
low, which would leave this mode +0.037 ppm against it - exact for the
NES and a near miss for the SNES it is named after - so PortareOS
patches it (`001-exact-ntsc-rate.patch`).

The cost is DSI bit clock, 1047.9MHz a lane against 939.9, up 11.5%, and
that is the part of this that is a test rather than a calculation. The
PHY on this SoC goes far higher; whether the panel controller takes it
is what the first boot answers. If it does not, the same mode at vtotal
1042 is -1.2ppm with 654.7us for 4.1% more clock, and 1001 is where it
started.

vtotal has to be even either way. The ideal clock is about 156497.31Hz
per line, so an even vtotal lands near a whole kHz and an odd one near
the half, which is the worst place to round from: 1041 would be +1.8ppm
where 1042 is -1.2. The 119.88 mode cannot be widened the
same way: its exactness needs `htotal * vtotal` divisible by 1001 and
`vtotal` supplies the 11 and the 13, so it only grows in steps of 143
lines, which would be 14% more bit clock.

The mode runs. The panel takes 174651 kHz at vtotal 1116, 1047.9MHz a
lane, and `modetest -c` lists it; RetroArch selects it by rate and logs
`one present a frame, 16.639 ms apart`, with no DSI or PHY errors in
dmesg. That answers the bit-clock question this mode was a test of.

The panel also keeps the rate it is given. Measured with `vblank-rate`
on the default mode, whose pixel clock the DSI PLL synthesises as
156239991 Hz against the 156240000 asked for: **119.88005 Hz over 20 s
and 119.88009 over 60, -0.50 and -0.17 ppm** from the 119.880113 those
timings work out to. This is a video-mode panel, so the DPU drives the
timing and the rate is the pixel clock over `htotal x vtotal`; the
measurement says the chain delivers that.

**Measure against `CLOCK_MONOTONIC_RAW`, not `CLOCK_MONOTONIC`.** DRM
timestamps vblanks with `ktime_get()`, which NTP slews; the pixel clock
is not slewed, so on a device running timesyncd the slew is measured as
if it were panel error. Here that was +68 ppm drifting to +70, and the
slew was separately seen swinging between -114 and -142 ppm between
runs - orders of magnitude more than the mode errors this table is cut
to. `vblank-rate` samples both clocks and reports both rates.

Still unverified, and it needs BFI on, which it was not for any of the
above: whether the wide blanking actually fixes the missed-flip band,
which is what E3's frametime harness with BFI is for - the band is
visible by eye, a few times a minute. The 120.197628 mode's own rate has
not been measured either; that needs a SNES game running to select it.

## Pacing: how a frame lands on a frame

A mode at twice the console's rate is only half of it. The other half is RetroArch holding the core to that mode, one frame for every two refreshes, with nothing else setting the pace.

RetroArch reaches the panel through Vulkan's `VK_KHR_display`, with no compositor. Its swap interval is left on automatic, which resolves to 2 when the mode is within the audio timing skew of twice the core's rate; that is what the modes are chosen for. Vulkan has no swap interval, so stock RetroArch keeps one by presenting the same frame twice into the FIFO swapchain. With two swapchain images, which the image uses for latency, the second present's acquire returns at the vblank between the two, and the core has one refresh period, 8.36 ms, to produce the next frame. A frame that takes longer costs a whole refresh. SwanStation at 4x with a CRT shader missed often enough for 55.65 fps against 59.83, with the audio buffer running dry every 50 to 100 ms and 5 to 8 ms gaps in the sound 7.5% of the time. That was the "slowed down" audio after threaded video was turned off.

Patch `0014-vulkan-khr-display-timed-presents.patch` presents each frame once instead, with a desired present time through `VK_GOOGLE_display_timing`: two refresh periods after the last present the driver has timed, counted per present issued since it. Mesa's KMS backend flips on exactly that vblank. The acquire then returns the moment the previous frame reaches the display, the core has the whole frame period, and the loop runs at the mode's rate, which is the console's. The last present's actual time is the anchor, so a late frame moves the cadence by a refresh and the next one is placed from where the display is, not from a schedule that has drifted. The repeat stays for contexts that cannot time a present. Two things in RetroArch had to be fixed for the extension to be usable at all: its entry points were only loaded on Windows, and a device negotiated by a hardware core, which is how SwanStation and the other Vulkan cores work, never had the extension enabled or recorded.

Measured on Tekken 3, threaded video off:

| Presents | Core fps | Audio gaps in 15 s |
|---|---|---|
| The same frame twice | 55.65 | 161 gaps of 5 to 8 ms, 7.5% of the time |
| One, timed | 59.64 | none |

The dropped-frame count was about ten in every run, all in the first seconds, while the core loads and the pipelines compile.

**Threaded video is off** (`video_threaded = "false"`). With it on, a worker thread presents whatever frame is latest and the core is paced by the audio sink instead: full speed and clean audio, but a thread hop of latency, frames reaching the panel unevenly, the core drifting against the panel by the difference of two clocks, and nothing for the automatic frame delay to measure. The exact modes buy nothing in that arrangement. It was the stopgap (#337) between finding the cause and fixing the driver (#339). A core that cannot make a frame inside 16.7 ms can still have it on in its own override file, `config/<core>/<core>.cfg`; better to find out why it is that slow.

With the core paced by the panel, audio rate control only absorbs the residual between the mode and the panel's crystal, a few parts per million, rather than the difference between the audio and video clocks. Where the mode is not exactly twice the core's rate, the arcade boards for instance, the skew is larger and rate control bends the pitch accordingly, as on any other device.

To see it working: the log has `Timed presents: swap interval 2, one present a frame, 16.683 ms apart.` when the path is in effect. A hardware-rendered core that creates its own Vulkan device has to enable `VK_GOOGLE_display_timing` for this, because RetroArch cannot add it afterwards. Flycast ignored the list it was given until its patch 002, and ran on the repeated presents. A core that still does gets `VK_GOOGLE_display_timing: not enabled on the device, presents are not timed.` in the log and falls back. RetroArch's statistics overlay (`statistics_show`) reports the core's frame rate, the loop deviation and the audio buffer's underruns. `vblank-rate` measures the panel's real rate without DRM master, from a queued DRM vblank event; `/sys/kernel/debug/dri/0/crtc-0/status` also counts vblanks but its counter only advances while the vblank IRQ is enabled, so it cannot be sampled against wall clock - an idle panel reads about 27 Hz on a 120 Hz mode. A capture of the PipeWire sink (`pw-record --target <sink> -P '{ stream.capture.sink = true }'`) shows audio gaps as runs of zero samples.

## Systems

The rates are the original NTSC hardware's frame rate, or for handhelds the hardware's own rate.

Where an emulator runs at a different rate from the hardware, the table says so. On the N64, the hardware rate follows from the video chip's 48.681812 MHz clock: a 3094-clock line and a 263-line frame in 240p, or 262.5 lines in 480i. ParaLLEl N64 as shipped upstream does not emulate the line length: it derives the frame period from a nominal 60 Hz and the frame height the game sets, so it runs at about 60.02 Hz. PortareOS patches it (`003-vi-frame-period-from-h-sync.patch`) to take the period from the `V_SYNC` and `H_SYNC` registers, which gives the console's 59.826 Hz, and matches a panel mode to it.

The PlayStation's line is 3412.5 GPU clocks, the broadcast line. SwanStation rounds it to 3413 and so runs at 59.8173 Hz; PortareOS patches it (`001-ntsc-line-is-3412-5-ticks.patch`) to alternate 3413 and 3412 like the console, which gives 59.826 Hz, the same as the N64, so the two share a mode. SwanStation keeps 263 lines in 480i as well, where the console has 262.5, so a 480i game runs at 59.826 rather than the console's 59.94: 0.19 % slow, the same compromise as the N64's.

| Systems (default emulator) | Native rate (Hz) | Panel mode (Hz) |
|---|---|---|
| gb, gbh, gbc, gbch (Gambatte) | 59.7275 | 119.455 |
| gba, gbah, gbav (mGBA) | 59.7275 | 119.455 |
| snes, snesh, sfc, satellaview, sufami, snesmsu1 (Snes9x) | 60.0988 | 120.198 |
| nes, famicom, fds (Nestopia) | 60.0988 | 120.198 |
| psx (SwanStation) | 59.826 (480i too, see above) | 119.652 |
| saturn (Beetle Saturn) | 59.826 (the core reports it exactly with our patch; in 480i the emulated fields alternate 262 and 263 lines, the reported rate stays) | 119.652 |
| mastersystem, sg-1000, gamegear, ggh (Genesis Plus GX) | 59.9227 | 119.846 |
| megadrive, megadrive-japan, megadriveh, genesis, genh (Genesis Plus GX) | 59.9227 | 119.846 |
| segacd, megacd (Genesis Plus GX) | 59.9227 | 119.846 |
| sega32x (PicoDrive) | 59.9227 (the emulator reports 60) | 119.880 |
| n64, n64dd (ParaLLEl N64) | 59.826 in 240p, 59.94 in 480i | 119.652 |
| neogeo (FBNeo) | 59.1856 (the emulator keeps hundredths: 59.18) | 118.360 |
| neocd (NeoCD) | 59.5999 (the CD's 24.168 MHz crystal) | 119.200 |
| arcade (FBNeo) | depends on the game's board (about 54–61) | 119.880 |
| dreamcast, naomi, atomiswave (Flycast) | 59.94 | 119.880 (exactly 2×) |
| gamecube, triforce, wii, wiiware (Dolphin) | 59.94 | 119.880 (exactly 2×) |
| ps2 (ARMSX2) | 59.94 | 119.880 (exactly 2×) |
| xbox (xemu) | 59.94 | 119.880 (exactly 2×) |
| psp, pspminis (PPSSPP) | 59.94 | 119.880 (exactly 2×) |
| scummvm, steam, ports | no fixed rate (PC games) | 119.880 |
| movies (mpv) | the video's frame rate (23.976, 25, 29.97 …) | 119.880; mpv syncs video to audio |
| music, tools, imageviewer | – | 119.880 |

## Audio

The Nova's speaker and headphone link runs at **48 kHz, 44.1 kHz or 32 kHz**. Three things had to allow that: the AudioReach topology blob, which caps the playback PCMs at 48 kHz until `extra-firmware`'s `tplg-playback-rates.py` widens it; kernel patches 1052–1055, which open the DSP ports and the machine driver's fixup to 44.1 and 32 kHz; and the I2S bit clock, which follows the stream (1054). PipeWire allows all three rates (`default.clock.allowed-rates = [ 48000 44100 32000 ]`). [AUDIO_SAMPLE_RATES.md](AUDIO_SAMPLE_RATES.md) describes the whole procedure, for carrying it to another distribution. No rate is a resampling stage in itself: the link switches to the rate of the stream that opens it.

**RetroArch picks the link rate from the core's** (`audio_out_rate = "0"`, RetroArch patch 0015): the smallest of 32, 44.1 and 48 kHz that the core's rate divides into within 0.5 % (32,040 → 32,000; 22,050 → 44,100; 44,100 → 44,100), else the smallest above it so nothing is cut (32,768 → 44,100), else 48 kHz (65,536 → 48,000). The pick is made every time the audio driver initialises, so a core that changes its rate through `SET_SYSTEM_AV_INFO`, as ParaLLEl N64 does once the game has programmed its DAC, reopens the device at the new game's rate. A non-zero `audio_out_rate` in a per-core config (`config/<core>/<core>.cfg`) still overrides the pick; the shipped ones for SwanStation, Flycast, PPSSPP, NeoCD, Genesis Plus GX, PicoDrive (44.1 kHz) and Snes9x (32 kHz, 44.1 kHz for `snesmsu1`) name the rate the pick would make anyway. RetroArch resamples each core's audio to that rate with its sinc resampler, and dynamic rate control keeps the stream in step with the display. So every core is resampled at least a little, even one whose rate matches the output, because rate control adjusts the ratio by up to 0.5 %. mpv plays a file at its own rate.

The first rate column is the console's own: the rate its sound hardware produces samples at, or "analog" where the chip's channels are mixed as analog signals and there is no sample rate to speak of. The second is what the emulator hands RetroArch, taken from its source code at the pinned commit with PortareOS's options.

| Systems (default emulator) | Console's audio rate (Hz) | Emulator outputs (Hz) | Played at (Hz) |
|---|---|---|---|
| gb, gbh, gbc, gbch (Gambatte) | analog (the APU runs at 1,048,576) | 32,768 | 48,000 |
| gba, gbah, gbav (mGBA) | 32,768 by default; a game can pick up to 262,144 | 65,536 | 48,000 |
| snes, snesh, sfc, satellaview, sufami (Snes9x) | 32,000 nominal (about 32,040 on real consoles) | 32,040 | 32,000 |
| snesmsu1 (Snes9x) | 32,000, plus the MSU-1's 44,100 | 44,100 (MSU-1 enhanced audio) | 44,100 |
| nes, famicom, fds (Nestopia) | analog (the APU's channels are mixed as analog signals) | 48,000 (mixed at the APU clock, decimated) | 48,000 |
| psx (SwanStation) | 44,100 | 44,100 | 44,100 |
| saturn (Beetle Saturn) | 44,100 (SCSP) | 44,100 | 44,100 |
| mastersystem, sg-1000, gamegear, ggh (Genesis Plus GX) | analog (SN76489, 223,722 per channel step) | 44,100 | 44,100 |
| megadrive, megadrive-japan, megadriveh, genesis, genh (Genesis Plus GX) | 53,267 (YM2612), plus the SN76489 | 44,100 | 44,100 |
| segacd, megacd (Genesis Plus GX) | as the Mega Drive, plus 32,552 (RF5C164 PCM) and 44,100 (CD audio) | 44,100 | 44,100 |
| sega32x (PicoDrive) | as the Mega Drive, plus the 32X's PWM at a rate the game sets | 44,100 (`native` would give 53,267) | 44,100 |
| n64, n64dd (ParaLLEl N64) | set by the game (commonly 22,050 to 44,100) | the game's rate, exactly, e.g. 22,037.94; 32,040 until the game sets one | the link rate picked for the game's: 32,000 for ~32 kHz games, 44,100 for ~22 kHz and 44.1 kHz ones |
| neogeo (FBNeo) | 55,555 (YM2610) | about 48,000 (47,990 at 59.18 fps) | 48,000 |
| neocd (NeoCD) | 55,555 (YM2610), plus 44,100 (CD audio) | 44,100 | 44,100 |
| arcade (FBNeo) | depends on the board | about 48,000, depending on the game's frame rate | 48,000 |
| dreamcast, naomi, atomiswave (Flycast) | 44,100 (AICA) | 44,100 | 44,100 |
| gamecube, triforce (Dolphin) | 32,029 (DSP), 48,000 (streamed disc audio) | 48,000 (asks RetroArch for its rate) | 48,000 |
| wii, wiiware (Dolphin) | 32,000 (DSP), 48,000 (streamed disc audio) | 48,000 (asks RetroArch for its rate) | 48,000 |
| ps2 (ARMSX2) | 48,000 (SPU2) | 48,000 (44,100 in PS1 mode) | 48,000 |
| xbox (xemu) | 48,000 (AC'97) | 48,000 | 48,000 |
| psp, pspminis (PPSSPP) | 44,100 | 44,100 | 44,100 |
| movies, music (mpv, PORTAMP) | the file's rate | the file's rate | the file's rate |

In short:

- **No resampling needed:** the 44.1 kHz cores play at 44.1 kHz: PS1, Saturn, Dreamcast, NAOMI, Atomiswave, PSP, NeoCD and every other Sega system. Xbox, PS2, Dolphin and Nestopia already produce 48 kHz.
- **Nearly native:** the SNES plays at 32 kHz. The 32,040 → 32,000 conversion (0.125 %) is smaller than what rate control adjusts anyway.
- **Resampled as on any other device:** Game Boy, GBA and Neo Geo. Their rates match none of the link's rates, so they need resampling either way. The N64 is per game: ~32 kHz games get the 32 kHz link, ~22 kHz games an exact 2:1 into 44.1 kHz, 44.1 kHz games play native.

## Adding a mode

1. Find the system's exact native rate `f`, preferably from the rate the emulator logs at startup.
2. Compute the pixel clock `round(2 × f × 1302 × 1001 / 1000)` in kHz, add the mode to the driver patch next to the others, and update the hunk's line count.
3. Add the emulator and the rate `2 × f` to `set_ra_refresh_rate` in `setsettings.sh`. RetroArch accepts a mode within 1 Hz of the requested rate, and `setsettings.sh` only asks for a mode that the panel lists within 0.002 Hz.
4. Test the mode on the device: `modetest -c` lists it, and the picture stays stable while a game runs.

Open work is tracked in #284.
