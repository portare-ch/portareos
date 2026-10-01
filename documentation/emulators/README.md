# Emulators

One file per emulator, holding what was found out about it on this device and
what was concluded: how it presents frames, how it is paced, where its threads
run, what was measured, and what is still open. The aim is that nobody has to
re-derive a decision, and that a later change can be checked against the
numbers that justified the current one.

| Emulator | Systems | File |
|---|---|---|
| ARMSX2 (libretro) | PS2 | [ARMSX2.md](ARMSX2.md) |

Each file keeps these sections, leaving out what does not apply:

- **What runs**: package, version, patches, frontend.
- **Presentation**: swapchain or not, how a frame reaches the panel.
- **Pacing**: what clock drives emulation, queue depths, latency.
- **Audio**: buffers, what is latency and what is only capacity.
- **CPU and core mapping**: which thread runs where and why, and the
  `coremap-check` layout that tests it.
- **Settings and why**: every non-default we force, with its reason.
- **Measurements**: date, build, game, settings, result. Append, do not
  rewrite.
- **Open questions**.

The core layout of the SoC that every mapping refers to is in
[../CPU_ISOLATION.md](../CPU_ISOLATION.md).
