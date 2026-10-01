# Roadmap

Last revised 30 September 2026.

The goal is a stock Android replacement for the Retroid Pocket Nova: write
an image, add games and any required BIOS files, and play. Every included
emulator should work with the built-in controls and ship with settings
chosen for this device. Low latency, reliable operation and faithful console
timing are the priorities.

The immediate priority is getting every included emulator running reliably
and configured properly. Latency experiments must also be tested across
systems before they become defaults. The work below has a next action and a
completion criterion; there are no release dates attached.

[BUGS.md](BUGS.md) holds observed failures and reproduction details. Hardware
test results should record the image version, game, settings and logs so
that a later image can be tested against the same baseline.

## Every included emulator runs without crashes

The README currently records successful tests for Snes9x and SwanStation,
and a broken Dolphin path: hangs and no sound
([#463](https://github.com/portare-ch/portareos/issues/463)). The rest of the
included systems need an explicit test record, not an assumption that a
successful build means a working emulator.

- Make a test matrix for every emulator in the
  [supported systems list](documentation/PER_DEVICE_DOCUMENTATION/SM8550/SUPPORTED_EMULATORS_AND_CORES.md).
  Cover launch, controls, video, audio, saving, loading, exiting and relaunching.
- Fix Dolphin's hangs and missing audio. Work through the other emulators
  with the same matrix, retaining logs and reproducible cases for failures.
- Test repeated launches, extended play, suspend/resume and return from game
  guides, including Vulkan cores that lose and recreate their graphics context.
- Separate game compatibility limits from failures in our build, launcher,
  configuration or device integration.

**Complete when:** every included emulator passes the matrix on the Nova,
with representative games and no crashes, hangs, missing audio or broken
return to the launcher in those tests. Remaining game-specific limitations
are documented with reproductions. Passing this matrix is the regression
baseline for later changes.

## Configure every system for plug-and-play use

Working emulators still need good defaults. A fresh install should not
require a trip through RetroArch or a standalone emulator's menus.

- Audit each system's controller mapping, hotkeys, save paths, BIOS handling,
  aspect ratio, scaling, shader, rendering resolution and performance settings.
- Choose defaults using actual games on the Nova. Test demanding games as
  well as easy ones; avoid a visual preset that causes missed frames or audio
  underruns. Add per-game overrides where a system-wide setting cannot work.
- Make save/load, exit and game-guide controls consistent where the emulator
  permits it. Explain missing BIOS files and unsupported formats clearly.
- Test both a clean installation and an update with existing user settings.

**Complete when:** games launch with usable controls, correct geometry,
clean audio and suitable performance without manual emulator configuration.
Required files and unavoidable exceptions are documented, and updates
preserve settings the user deliberately changed.

## MCU and input latency

The gamepad MCU now reports every 5 ms (200 Hz), versus the vendor's
9 ms (111 Hz). `rsinput.frame_rate=3` sets the scan delay from boot, with
a driver fix that makes command-line parameters safe before registration.
Probe and resume send the setting; UART measurements confirmed 200 Hz
across two suspend/resume cycles
([#466](https://github.com/portare-ch/portareos/pull/466)). At 250 Hz, about
19% of reports never reached evdev; the cause is not yet investigated.
Values 0 and 1 stopped the pad. Faster reporting is not yet evidence of
lower button-to-screen latency.

- Compare button-to-screen latency at the vendor setting and at 200 Hz.
  Establish a repeatable input trigger and camera measurement
  ([#13](https://github.com/portare-ch/portareos/issues/13)).
- Trace the lost reports at 250 Hz before considering a faster default.
  Measure report jitter, lost inputs and end-to-end latency; check buttons
  and analog sticks separately.
- Check the rest of the path through rsinput, InputPlumber and the emulator
  to identify where additional delay is introduced.
- Extend the 200 Hz tests under load and through repeated suspend/resume;
  measure power cost and stick noise before further tuning.

**Complete when:** a measured configuration improves input latency without
lost inputs, noisy controls or resume regressions, and the baseline and
results are published. Keep the vendor setting as the comparison baseline.

## Audio latency

RetroArch currently defaults to 8 ms. That setting is a buffer request, not
end-to-end latency. Existing measurements and the limits encountered are in
[the audio latency notes](docs/audio-latency.md).

- Measure end-to-end audio latency and audio/video alignment on the current
  image, rather than inferring them from the configured buffer size.
- Test 32, 44.1 and 48 kHz playback across all emulators, including standalone
  ones, on speakers and wired headphones. Record negotiated buffers, xruns
  and audible failures during extended play and rate changes between games.
- Locate the remaining delay before reducing buffers further. Test any
  driver, DSP or scheduling change against the emulator regression matrix.
- Measure idle wakeups, power use and suspend/resume with the tuned path.

**Complete when:** the shipped defaults have measured latency and stable
playback across the tested systems and wired outputs. Any lower-latency
change must show an improvement without crackle, dropouts or power/resume
regressions.

## Low-latency local audio and Bluetooth audio

Evaluate two audio profiles: a tightly tuned path for speakers and wired
headphones, and a Bluetooth-compatible path with the buffering and rate
handling it needs. Compatibility of Bluetooth with the current latency
tweaks is an open question to test.

- Pair a Bluetooth headset and establish which current settings work and
  which cause failures. Record routing, codec, rate and buffering.
- Determine whether separate PipeWire/WirePlumber profiles are sufficient
  or whether separate service configurations are needed.
- Switch profiles when the output changes, including connecting and
  disconnecting a headset during a game. Restore local latency settings
  when returning to speakers or wired headphones.
- Test pairing, reconnect, volume control, suspend/resume and failure recovery.

**Complete when:** local outputs retain their tuned latency, Bluetooth plays
reliably, and moving between them requires no manual service restart or
configuration edits. Document Bluetooth's measured latency separately.

## Black frame insertion

BFI has worked in Snes9x experiments, but rolling black bands and the
brightness tradeoff still prevent it from being a finished feature. Timing
work and panel modes are recorded in
[refresh rates](documentation/PER_DEVICE_DOCUMENTATION/SM8550/REFRESH_RATES.md).

- Reproduce and instrument the rolling band on the current image. Test flip
  deadlines, vertical blanking and CPU scheduling with controlled settings.
- Compare two- and three-image swapchains for stability and input latency.
- Measure brightness loss and choose an appropriate brightness adjustment.
- Test sustained play on each candidate core, including dropped frames,
  audio stability and transitions back to the launcher. Keep BFI opt-in
  and restrict it to configurations that pass.

**Complete when:** supported configurations sustain the light/black cadence
without rolling bands or missing content, with measured latency and
brightness behavior. Heavy cores need their own evidence before inclusion.

## Reduce the image further

Use the [package inventory](documentation/PACKAGE_INVENTORY.md) as the starting
point ([#333](https://github.com/portare-ch/portareos/issues/333)). It lists
roughly 100 MB of candidates: unused shader families, Python and GStreamer.
Those are estimates of installed space, not promised compressed-image savings.

- Measure the current compressed image and installed package sizes.
- Keep only the shaders in use and their transitive includes; launch every
  affected preset to check that the trimmed set is complete.
- Remove Python only after replacing its runtime users, including Bluetooth
  pairing, and checking the Steam dependency path.
- Trace GStreamer's users and remove it if the retained features can run
  without it. Continue removing unused packages and shadowed recipes.

**Complete when:** each removal has a measured before/after size and passes
its affected runtime checks. Publish the resulting image size; do not trade
working emulators, Bluetooth or required tools for a smaller headline number.

## ARMSX2 through libretro

PS2 runs ARMSX2's libretro core in RetroArch; the standalone SDL frontend
is gone. BIOS images in `bios/armsx2` are copied to `bios/pcsx2/bios` on
update, and the memory cards stay in the `ps2` folder.

- Get back what the standalone had. The first Nova test (Time Crisis II,
  upstream's generic CI build of the core) ran slower and with more
  visible glitches. Leads, from the two configurations side by side:
  - Texture barriers: the standalone forced them off
    (`OverrideTextureBarriers = 0`); the core's automatic turns them on,
    and a barrier is expensive on a tiler.
  - Pacing, done: the core now takes RetroArch's frame rate as the host
    refresh rate and lets the hand-off to `retro_run` pace it, one clock
    (patch 001).
  - `VsyncQueueSize`, done: 0 as in the standalone (patch 001). Step to 1
    only if 0 cannot hold full speed.
  - Clocks and core layout: schedutil clocked the big cores down because
    the core's threads take turns within a frame (40 fps against 59.7 on
    performance). PS2 now runs on performance, with EE pinned to the X3 and
    VU and GS to the A715s. Research and measurements in
    `documentation/emulators/ARMSX2.md`.

  Texture barriers are not a core option; the core keeps them in
  `<system>/pcsx2/inis/armsx2-libretro.ini`. Measure on its own.
- Compare it with what the standalone did on the same games: compatibility,
  speed, frame pacing, input/audio latency, controls and save behavior.
- RetroAchievements: the core exposes no memory to RetroArch, so PS2 has
  none. The standalone had them built in.

**Complete when:** the core matches the standalone's Nova results, or each
gap has an issue.

## Fix external display support

- Reproduce the current failures with USB-C displays and adapters. Record
  connector detection, available modes, DRM ownership and emulator logs.
- Make the launcher and each rendering path select and release the external
  output correctly, with suitable resolution, refresh rate and aspect ratio.
- Test connection before boot, connection during use, disconnection during
  a game and return to the internal panel. Handle unsupported modes cleanly.
- Verify external audio routing where available and recovery to local audio.

**Complete when:** the launcher and included emulators work on tested external
outputs, and connection/disconnection recovers without a black screen,
crash or reboot. Publish tested adapters, displays and remaining limitations.

## Other work to retain

- **Suspend and resume:** measure actual suspend current and overnight drain,
  identify the remaining power holders, and reduce Wi-Fi reconnect time.
  Verify repeated sleep/wake cycles with working controls and audio
  ([#62](https://github.com/portare-ch/portareos/issues/62)).
- **Implement all remaining panel modes:** inventory the missing modes for
  supported systems, including 32X, Dreamcast 240p and arcade board rates.
  Add the modes and any core reporting or mode-selection fixes they need;
  verify every mode on hardware against the core's output, including switching
  between games and returning to the launcher
  ([#284](https://github.com/portare-ch/portareos/issues/284)).
- **Move off the 7.2.5 kernel pin:** reproduce and isolate the Wi-Fi regression recorded
  against the 7.2.5 pin before moving it
  ([#194](https://github.com/portare-ch/portareos/issues/194)).
- **Launcher:** finish navigation and selection persistence, expose game
  launch failures, and integrate M1/M2 controls. Coordinate implementation
  with the portarelauncher repository.
- **Color profiles:** fix crushed dark greys and verify the result on the
  panel before recommending a calibrated profile again; see BUGS.md.
- **A game session that is not root:** move game sessions to a dedicated user
  and verify access to
  saves, devices and launcher handover
  ([#204](https://github.com/portare-ch/portareos/issues/204)).

## Scope

Retroid Pocket Nova only, NTSC focused, one emulator per system and direct
KMS presentation. Other devices, PAL panel modes and a desktop compositor
are not planned.
