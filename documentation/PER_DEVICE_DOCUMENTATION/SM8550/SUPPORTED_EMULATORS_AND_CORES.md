# Game folders, formats and emulators

Reviewed 24 October 2026 against the
[system definitions](https://github.com/portare-ch/portareos/tree/next/config/emulators) and
[emulator selection](https://github.com/portare-ch/portareos/blob/next/packages/virtual/emulators/package.mk).
Folder names below are relative to `/storage/roms/` unless an absolute path
is shown. Required BIOS files go under `/storage/roms/bios/` in the layout
the emulator expects.

**Use CHD for disc games; cartridge games keep their ROM formats.**
PlayStation, PlayStation 2, Dreamcast, Saturn, Sega CD and Neo Geo CD
enforce CHD-only images. All but Neo Geo CD also accept `.m3u`
playlists naming CHDs. Xbox takes XISO (`.iso`) images, or CHDs
made from them with `chdman createdvd`. PSP takes CHD, or PBP for homebrew, PSN titles and Minis.
GameCube and Wii take RVZ,
Dolphin's lossless format, which compresses these discs far better than CHD;
`.dol` homebrew and `.wad` channels stay. Arcade sets and floppy-disk images
keep their own formats.

**One folder per system, named for the US console.** A region's, a
console add-on's or a ROM hack's games go in their console's folder:
Mega Drive and its hacks in `genesis`, Mega-CD in `segacd`, Super Famicom,
Satellaview, MSU-1 and hacks in `snes`, Famicom and Famicom Disk System in
`nes`, 64DD disks in `n64`, PSP Minis in `psp`, WiiWare in `wii`, and the
Game Boys' and Game Gear's hacks in theirs. An update from a release with
the separate folders moves their games, saves, settings and save states
over.

The extension list describes what the launcher recognizes, not a guarantee
of compatibility or tested performance. See [known issues](../../../BUGS.md)
for Dolphin and other open checks. `folders` in the music row means an album
directory can be selected for playback.

The Screenshots system lists the recognized files, but no image viewer is
configured to open them from that row.

Use [PortareOS tools / nova-push](https://github.com/portare-ch/portareos_tools)
for conversion, verification and transfer. Follow the
[installation guide](../../INSTALLATION.md#recommended-portareos-tools-and-nova-push)
for setup and examples.

|Manufacturer|System|Release Date|Games Path|Recognized Extensions|Emulator / Core|
|----|----|----|----|----|----|
|&#xf013; System|Movies (movies)|System|`movies`|.3g2 .3gp .asf .avi .divx .f4v .flv .m2ts .m3u .m4v .mkv .mov .mp4 .mpeg .mpg .mts .ogm .ogv .ts .vob .webm .wmv|**mpv:** mpv (default)<br>|
|&#xf013; System|Music Player (music)|System|`music`|.aac .ape .flac .m3u .m4a .mp2 .mp3 .oga .ogg .opus .wav .wma .wv folders|**portamp:** portamp (default)<br>|
|&#xf013; System|Screenshots (imageviewer)|System|`screenshots`|.jpg .jpeg .png .bmp .psd .tga .gif .hdr .pic .ppm .pgm .mkv .pdf .mp4 .avi||
|&#xf013; System|Tools (tools)|System|`/storage/.config/modules`|.sh||
|Arcade|Arcade (arcade)|0000|`arcade`|.zip .7z|**retroarch:** fbneo (default)<br>|
|Microsoft|Xbox (xbox)|2001|`xbox`|.iso .chd|**retroarch:** hakux (default)<br>|
|Nintendo|Game Boy (gb)|1989|`gb`|.gb .gbc .zip .7z|**retroarch:** gambatte (default)<br>|
|Nintendo|Game Boy Advance (gba)|2001|`gba`|.gba .zip .7z|**retroarch:** mgba (default)<br>|
|Nintendo|Game Boy Color (gbc)|1998|`gbc`|.gb .gbc .zip .7z|**retroarch:** gambatte (default)<br>|
|Nintendo|GameCube (gamecube)|2001|`gamecube`|.rvz .dol .m3u|**retroarch:** dolphin (default)<br>|
|Nintendo|Nintendo 64 (n64)|1996|`n64`|.z64 .n64 .v64 .ndd .zip .7z|**retroarch:** parallel_n64 (default)<br>|
|Nintendo|Nintendo Entertainment System (nes)|1985|`nes`|.nes .unif .unf .fds .zip .7z|**retroarch:** mesen2 (default)<br>|
|Nintendo|Super Nintendo (snes)|1991|`snes`|.smc .fig .sfc .swc .bs .bsx .zip .7z|**retroarch:** snes9x (default)<br>|
|Nintendo|Wii (wii)|2006|`wii`|.rvz .dol .wad .m3u|**retroarch:** dolphin (default)<br>|
|Sammy|Atomiswave (atomiswave)|2003|`atomiswave`|.lst .bin .dat .zip .7z|**retroarch:** flycast (default)<br>|
|Sega|Dreamcast (dreamcast)|1998|`dreamcast`|.chd .m3u|**retroarch:** flycast (default)<br>|
|Sega|Game Gear (gamegear)|1990|`gamegear`|.bin .gg .zip .7z|**retroarch:** genesis_plus_gx (default)<br>|
|Sega|Genesis (genesis)|1989|`genesis`|.bin .gen .md .sg .smd .zip .7z|**retroarch:** genesis_plus_gx (default)<br>|
|Sega|Master System (mastersystem)|1985|`mastersystem`|.bin .sms .zip .7z|**retroarch:** genesis_plus_gx (default)<br>|
|Sega|Naomi (naomi)|1998|`naomi`|.lst .bin .dat .zip .7z|**retroarch:** flycast (default)<br>|
|Sega|Saturn (saturn)|1994|`saturn`|.chd .m3u|**retroarch:** ymir (default)<br>|
|Sega|Sega 32X (sega32x)|1994|`sega32x`|.32x .smd .bin .md .zip .7z|**retroarch:** picodrive (default)<br>|
|Sega|Sega CD (segacd)|1991|`segacd`|.chd .m3u|**retroarch:** genesis_plus_gx (default)<br>|
|Sega|SG-1000 (sg-1000)|1983|`sg-1000`|.bin .sg .zip .7z|**retroarch:** genesis_plus_gx (default)<br>|
|SNK|Neo Geo (neogeo)|1990|`neogeo`|.7z .zip .neo|**retroarch:** fbneo (default)<br>|
|SNK|Neo Geo CD (neocd)|1994|`neocd`|.chd|**retroarch:** neocd (default)<br>|
|Sony|PlayStation (psx)|1994|`psx`|.chd .m3u|**retroarch:** swanstation (default)<br>|
|Sony|PlayStation 2 (ps2)|2000|`ps2`|.chd .m3u|**retroarch:** armsx2 (default)<br>|
|Sony|PlayStation Portable (psp)|2004|`psp`|.chd .pbp|**retroarch:** ppsspp (default)<br>|
|Valve|Steam (steam)|System|`/storage/.local/share/applications`|.desktop|**steam:** steam (default)<br>|
|Various|ScummVM (scummvm)|2001|`scummvm`|.scummvm .svm|**retroarch:** scummvm (default)<br>|
