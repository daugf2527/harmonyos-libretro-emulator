# Built-in ROM Test Set

This directory contains the local ROM/content samples bundled for emulator
runtime testing.

The app scans this directory through `refactoredGetRawFileListAsync()` and
exposes matching files in the library as `BUNDLED` records. Paths are launched
as rawfile paths such as `roms/gb_gbc/snake_v0.1.gb`.

Current coverage:

- `gb_gbc/`: GB/GBC content for Gambatte, SameBoy, and mGBA compatibility tests.
- `gba/`: GBA content for mGBA and Beetle GBA tests.
- `nes/`: NES content for Nestopia, FCEUmm, QuickNES, and Mesen tests.
- `snes/`: SNES content for Snes9x, Snes9x 2010, and bsnes-hd tests.
- `md/`: Mega Drive / Genesis content for Genesis Plus GX tests.
- `arcade/`: ZIP content for FBNeo/MAME smoke tests.
- `misc/`: PICO-8, PS cue/bin, and core-specific data package samples.

Do not replace these files with empty placeholders. If a sample must be
removed, update the scanner expectations and test notes in the same change.
