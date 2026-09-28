# Roadmap

Intent, not promise. Ordered roughly by how much difference each would make.
Last revised 26 September 2026, at nightly 149.

## The goal

A straight replacement for the stock Android install. Write the card, copy the
games across, and every emulator is already set up for this handheld. Not
generic defaults, but per-system settings picked for the Nova. Latency first,
because that is what Android on this device is worst at, then correctness of
rates and geometry, then performance and visuals wherever they can be had
without being paid for in input lag.

## Where it stands

What the earlier roadmap listed as planned has largely landed. sway and
EmulationStation are gone; every program takes the panel through KMS and
[portarelauncher](https://github.com/portare-ch/portarelauncher) is the
front-end. The panel runs one mode per console family and RetroArch times each
frame to its vblank. The audio link follows the stream at 32, 44.1 or 48 kHz
and RetroArch picks the rate from the core's, per game on the N64. The
pulse-free audio stack, the color profile, the incremental build and the
package purge (about 250 MB) are in. Details are in the README and in
`documentation/`.

Most of it was tested on the device by the person who wrote it, some of it
only by ear, and the last day's changes not at all yet (see BUGS.md). There
is still no test rig: a 240 fps camera and a way to trigger a known input.

## Planned

### Verify the last day on hardware

Four changes went into `next` on 26 September without a device run: the
charger current limit and the throttle that drives it (#354, #355),
RetroArch's automatic output rate (#356), and strace 7.2 (#357). Each has its
check written down in BUGS.md. Doing them is the first job, before anything
is built on top.

### Suspend that costs nothing

Tracked in [#62](https://github.com/portare-ch/portareos/issues/62). The
device still loses charge overnight. Three hypotheses were tested and were
wrong; DDR never reaches its 200 MHz floor and the reason is not known. The
next step has not changed since the last revision of this file: measure
`current_now` in suspend instead of proxies, then find out which of the CX
holders (the gamepad's UART, PCIe for Wi-Fi, the display controller) keeps the
SoC up. Resume is at about 10 s to Wi-Fi association and the split is known;
the scan is the target.

### Black frame insertion

A 120 Hz panel showing 60 Hz content can spend the second refresh on black,
for CRT-like motion clarity. `video_black_frame_insertion` is 0 today. It
works on snes9x and looks right; one artefact is in the way.

Measured, snes9x at the exact 120.1976 mode, swap interval 1, BFI 1:

| swapchain images | presents / refreshes in 20 s | rate | flicker |
|---|---|---|---|
| 2 | 2231 / 2404 | 111.6 fps | constant |
| 3 | 2403 / 2404 | 120.2 fps | none seen |

Three images is the whole difference, for the reason ParaLLEl N64 and
Dolphin need it: the black frame is presented inside the frame call, and
with two images the acquire blocks until the light frame is off screen,
halving what the core has. At two images a seventh of the refreshes carry
no new frame and the strobe breaks; at three it does not.

What is left is a black band rolling down the panel, a few times a minute,
content missing inside it. The mechanism is known: a slipped flip inverts
the light/dark alternation. Forced onto the wrong mode (119.88, where the
core must lose a frame every 6.3 s) it appeared every 6 to 8 s, which is
that prediction.

Ruled out, each with a measurement: dropped presents (the present count
matches the refresh count), DSI tearing (`MIPI_DSI_MODE_VIDEO`, no
command-mode latch to tear), automatic frame delay (off changed nothing),
GPU devfreq (flat at 401 MHz, no transitions), and the PLL missing the
modeline (`dsi0_pll_bit_clk` 937,439,941 Hz against an ideal 937,440,000,
0.063 ppm, a frame of drift every 73 hours).

Two candidates remain. CPU frequency scaling is untested - the run that
looked like a negative had its governor reset by the launch, so it proved
nothing, and redoing it costs minutes over SSH. The other is the vertical
blanking window: 41 lines is 340.8 us to land a flip, BFI meets that
deadline twice as often as anything else, and three misses in 10,800 is
the 0.028% that would follow. `bfi-taller-vblank` widens it to 647.3 us
for 4% more DSI bit clock; unbuilt.

Brightness loss is real and unmeasured. BFI halves the duty cycle, and
whatever ships should raise the panel with it.

Not for the heavy cores. Dolphin glitched and crashed on Soulcalibur II
when this was last tried, and the blocking above says why.

### The last 130 MB

From `documentation/PACKAGE_INVENTORY.md`: slang-shaders trimmed to the three
families in use (~60 MB), Python replaced under the Bluetooth pairing agent
(34 MB), GStreamer (8 MB), gconv and locales (~25 MB). Tracked in
[#333](https://github.com/portare-ch/portareos/issues/333).

### Panel modes still open

[#284](https://github.com/portare-ch/portareos/issues/284) and
`documentation/PortareOS_Modelines.md`: the 32X, whose core reports a flat
60 Hz; Dreamcast games in 240p at 59.827 Hz; and arcade boards, which run at
whatever their board did. Each needs either a core fix or a mode of its own.

### Move off the 7.2.5 kernel pin

[#194](https://github.com/portare-ch/portareos/issues/194): 7.2.6 breaks
the WCN7850's firmware load and Wi-Fi never comes up. The regression is
upstream, between 7.2.5 and 7.2.6, and needs bisecting before the kernel can
move.

### Measure, then tune

The performance and latency work so far was reasoned, not measured: the 1000
Hz tick, teo, schedutil with the energy model, the two-image swapchain, timed
presents. A camera at 240 fps pointed at the panel and a button wired to a
GPIO would turn the remaining decisions (frame delay, BFI, thread pinning to
the Cortex-X3, the `irqaffinity=0-2` and `096-cpuidle` inheritances) into
numbers. [#13](https://github.com/portare-ch/portareos/issues/13).

### The launcher

Its own repository and its own issues. Open here:
[#258](https://github.com/portare-ch/portareos/issues/258) page and letter
jumps, [#259](https://github.com/portare-ch/portareos/issues/259) remember
the selected game, [#260](https://github.com/portare-ch/portareos/issues/260)
say when a game exits with an error,
[#226](https://github.com/portare-ch/portareos/issues/226) M1 and M2 through
InputPlumber.

### A game session that is not root

[#204](https://github.com/portare-ch/portareos/issues/204). Everything runs
as root today, as it did upstream. A dedicated user for the emulators is the
right shape; what it costs is every path that assumes `/storage` is writable
by whoever asks.

## Not planned

Support for any device other than the Retroid Pocket Nova. PAL modes. A
compositor. More than one emulator per system. See the README's rules.
