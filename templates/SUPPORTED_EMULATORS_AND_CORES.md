# Game folders, formats and emulators

Reviewed 29 October 2026 against the
[system definitions](../../../config/emulators) and
[emulator selection](../../../packages/virtual/emulators/package.mk).
Folder names below are relative to `/storage/roms/` unless an absolute path
is shown. Required BIOS files go under `/storage/roms/bios/` in the layout
the emulator expects.

**Use CHD for disc games; cartridge games keep their ROM formats.**
PlayStation, PlayStation 2, Dreamcast, Saturn, Sega CD and Neo Geo CD
enforce CHD-only images. All but Neo Geo CD also accept `.m3u`
playlists naming CHDs. Xbox takes only CHDs made from XISO images with
`chdman createdvd`. PSP takes CHD, or PBP for homebrew, PSN titles and Minis.
GameCube and Wii take RVZ,
Dolphin's lossless format, which compresses these discs far better than CHD;
`.dol` homebrew and `.wad` channels stay. Arcade sets and floppy-disk images
keep their own formats.

The extension list describes what the launcher recognizes, not a guarantee
of compatibility or tested performance. See [known issues](../../../BUGS.md)
for Dolphin and other open checks. `folders` in the music row means an album
directory can be selected for playback.

Use [PortareOS tools / nova-push](https://github.com/portare-ch/portareos_tools)
for conversion, verification and transfer. Follow the
[installation guide](../../INSTALLATION.md#recommended-portareos-tools-and-nova-push)
for setup and examples.

