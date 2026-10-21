# Roadmap

Last revised 21 October 2026.

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

Current baseline: Snes9x is the SNES core; NeoCD's device tuning is finished;
PlayStation has an optional PRMPT switch again. VRR spans 65–120.198 Hz for
RetroArch, the launcher and Steam's gamescope on the built-in panel, with
Steam capped at 60 fps. DisplayPort Adaptive-Sync is implemented, with
broader display and hotplug validation pending.
Platform sleep now works, measured at 23 mA over ten minutes. Black frame
insertion was removed with vsync and is outside the plan.

## Every included emulator runs without crashes

The README records successful tests for SwanStation, Snes9x and NeoCD,
playable ARMSX2 with further work pending, and a broken Dolphin path:
hangs and audio problems
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
- Keep the installation guide and format table aligned with the launcher.
  CHD is the disc-library format; PlayStation, PS2, Dreamcast and Neo Geo CD
  already enforce it. Recommend PortareOS tools / nova-push and document
  cartridge formats and experimental emulator exceptions explicitly.

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
  to identify where additional delay is introduced. The existing
  [per-system traces](documentation/LATENCY.md) measure pad polling to first
  scanline, not physical button-to-screen latency or MCU improvement.
- Extend the 200 Hz tests under load and through repeated suspend/resume;
  measure power cost and stick noise before further tuning.

**Complete when:** a measured configuration improves input latency without
lost inputs, noisy controls or resume regressions, and the baseline and
results are published. Keep the vendor setting as the comparison baseline.

## Audio latency

RetroArch currently defaults to 8 ms. That setting is a buffer request, not
end-to-end latency. Existing measurements and the limits encountered are in
[the audio latency notes](documentation/AUDIO_LATENCY.md).

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

## Reduce host cost without increasing latency

NeoCD's completed tuning exposed a system-wide cost: real-time audio and
GPU threads keep the X3 at its maximum clock while using about 1% of a core.
The global RT clamp at zero and two coarse placement changes were measured
and rejected. See [NeoCD](documentation/emulators/NeoCD.md) and the
[performance plan](documentation/PERFORMANCE_PLAN.md).

- Measure per-thread utilization clamping or a kernel policy against the
  existing capture, keeping audio latency, xruns and frame delivery fixed.
- Compare the 401 MHz gaming GPU floor with lower available frequencies on
  light cores; include demanding games before changing a shared default.
- Use validated captures, three repeated runs, separate intro/gameplay
  windows and current configuration records for each candidate.
- Validate Steam's VRR and 60 fps cap with a real game on the final kernel
  and gamescope, including focus changes and return to the launcher.

**Complete when:** a change reduces measured cost beyond run-to-run spread,
with stable audio, frame delivery and latency across the affected systems.

## Reduce the image further

Use the [package inventory](documentation/PACKAGE_INVENTORY.md) as the starting
point ([#333](https://github.com/portare-ch/portareos/issues/333)). Its size
figures come from an older image. Recheck unused shader families, Python's
remaining runtime users before treating them as savings. GStreamer and its
plugins, libmpeg2, x264 and x265 were removed as unreachable recipes in #701;
they were not installed in the image, so that removal saved no image space.

- Measure the current compressed image and installed package sizes.
- Keep only the shaders in use and their transitive includes; launch every
  affected preset to check that the trimmed set is complete.
- The Bluetooth agent is already C. Check remaining Python users, including
  `gamecapture` and Steam's dependency path, before proposing removal.
- Continue removing unused packages after checking every build stage;
  distinguish recipe maintenance reductions from installed-size savings.

**Complete when:** each removal has a measured before/after size and passes
its affected runtime checks. Publish the resulting image size; do not trade
working emulators, Bluetooth or required tools for a smaller headline number.

## ARMSX2 through libretro

PS2 runs ARMSX2's libretro core in RetroArch; the standalone SDL frontend
is gone. BIOS images in `bios/armsx2` are copied to `bios/pcsx2/bios` on
update, and the memory cards stay in the `ps2` folder.

- Recheck the first Nova test's gaps: Time Crisis II on upstream's generic
  CI core ran slower and with more visible glitches than the standalone.
  Several changes are already in the image:
  - Feedback-loop ordering: Mesa patch 009 and core patch 005 carry the
    ARMSX2 Turnip fix in the system driver. NFSU savestate tests held
    59.9–60.0 fps; driven races and read-back-heavy games still need tests.
  - Pacing, done: the core now takes RetroArch's frame rate as the host
    refresh rate and lets the hand-off to `retro_run` pace it, one clock
    (patches 001 and 006).
  - `VsyncQueueSize`, done: 0 as in the standalone (patch 001). Step to 1
    only if 0 cannot hold full speed.
  - Clocks and core layout: schedutil clocked the big cores down because
    the core's threads take turns within a frame (40 fps against 59.7 on
    performance). PS2 now runs on performance, with EE pinned to the X3 and
    VU and GS to the A715s. Research and measurements in
    [ARMSX2 notes](documentation/emulators/ARMSX2.md).

  Any further texture-barrier experiment must compare against this driver
  path, keeping rendering correctness and the scene fixed. The override
  lives in `<system>/pcsx2/inis/armsx2-libretro.ini`, not a core option.
- Compare it with what the standalone did on the same games: compatibility,
  speed, frame pacing, input/audio latency, controls and save behavior.
- RetroAchievements: the core exposes no memory to RetroArch, so PS2 has
  none. The standalone had them built in.

**Complete when:** the core matches the standalone's Nova results, or each
gap has an issue.

## Fix external display support

The monitor now replaces the internal panel (#710). Kernel fixes address
USB host-mode teardown and the DisplayPort unplug interrupt storm (#708,
#711), cap DP output at 8 bpc (#713), and add Adaptive-Sync with an effective
floor of at least 65 Hz (#714, #716). NeoCD was measured at 59.62 fps and
119.24 Hz on the LG UltraGear+ using the #714 test kernel; that does not
verify every rendering path or the later floor change.

- Validate USB-C displays and adapters on the current image. Record
  connector detection, available modes, DRM ownership and emulator logs.
- Check output selection and release on the launcher and each rendering
  path, with suitable resolution, refresh rate and aspect ratio.
- Verify Adaptive-Sync detection, the effective VRR range and integer-multiple
  repeats on the monitor itself; check fixed refresh on unsupported sinks.
- Test connection before boot, connection during use, disconnection during
  a game and return to the internal panel. Handle unsupported modes cleanly.
- Confirm sound stays on the local outputs when connecting or disconnecting
  a display. DisplayPort audio was deliberately removed (#709).

**Complete when:** the launcher and included emulators work on tested external
outputs, and connection/disconnection recovers without a black screen,
crash or reboot. Publish tested adapters, displays and remaining limitations.

## Direct Video Output for RetroTINK 4K

**Planned; extensive work.** Send the emulator's native video directly to
a RetroTINK 4K over HDMI, bypassing PortareOS video scaling, filtering and
added frame buffering. Send DV1 metadata with the signal so the RetroTINK
can recover the source geometry and perform pixel-perfect scaling and
filtering itself. RetroTINK's
[firmware notes](https://retrotink-llc.github.io/firmware/4k.html)
describe DV1 auto-cropping, auto-decimation and profile loading by core name.

- Establish the output path from each emulator through DRM/KMS and the
  Nova's USB-C DisplayPort-to-HDMI adapter. Verify that the adapter carries
  the required timings and DV1 metadata to the RetroTINK.
- Bypass shaders, display scaling and extra video queues in PortareOS.
  Preserve native pixels, aspect information and console timing, including
  resolution and progressive/interlaced changes during a game. Measure the
  remaining rendering and scanout latency.
- Implement DV1 metadata generation and HDMI transmission using the existing
  protocol as the reference. Verify source dimensions, crop and pixel
  repetition information, and core identification for automatic profiles.
- Validate on a real RetroTINK 4K with pixel patterns and representative
  games: correct detection, geometry, scaling, filtering, mode transitions
  and stable frame delivery. Record firmware, adapter, timings and latency.
- Test launcher handover, hotplug and return to the built-in panel, and
  document which emulators and adapters support Direct Video.

**Complete when:** supported emulators deliver unscaled source pixels and
correct DV1 metadata over HDMI, the RetroTINK applies the intended scaling
and filtering, and measurements confirm that PortareOS adds no video
scaling or avoidable frame queue. Hardware results and limitations are
published.

<!-- Tracking issue to be linked once opened. -->

## Other work to retain

- **Suspend and resume:** #658 enables CX, AOSS and DDR sleep. The
  18 October test measured 23 mA over ten minutes and Wi-Fi back within a
  second. Measure an overnight run, repeated short cycles, an open playback
  PCM at suspend, charger attachment asleep and working audio after wake;
  retain sleep-ledger and counter evidence in [power notes](documentation/POWER.md)
  ([#62](https://github.com/portare-ch/portareos/issues/62)).
- **Implement all remaining panel modes:** inventory the missing modes for
  supported systems, including 32X, Dreamcast 240p and arcade board rates.
  Add the modes and any core reporting or mode-selection fixes they need;
  verify every mode on hardware against the core's output, including switching
  between games and returning to the launcher
  ([#284](https://github.com/portare-ch/portareos/issues/284)).
- **Launcher:** test current navigation and selection persistence, error
  reporting, game-guide handover and update behavior. Coordinate changes
  with portarelauncher; the image currently ships 0.8.4.
- **Color profiles:** fix crushed dark greys and verify the result on the
  panel before recommending a calibrated profile again; see BUGS.md.
- **A game session that is not root:** move game sessions to a dedicated user
  and verify access to
  saves, devices and launcher handover
  ([#204](https://github.com/portare-ch/portareos/issues/204)).

## Scope

Retroid Pocket Nova only, NTSC focused, one emulator per system and direct
KMS presentation. Steam uses gamescope as its compositor exception. Other
devices, PAL panel modes, black frame insertion and a desktop environment
are not planned.
