# Arcadia Systems core -- status and measurements

MAME 0.289 is the reference (`src/mame/amiga/arsystems.cpp`, with MAME's Amiga chipset). The core is Minimig-AGA fixed to the
A500 (OCS, NTSC, 68000, 512 KB chip RAM) with the Arcadia board added (`docs/hardware.md`). The 22 working MAME 0.289 sets have
MRAs: 16 games and 6 other versions.

## Verified (2026-10-20 / 21)

The commands run from the repository's folder; ROM images and captures go to a scratch folder (`<romdir>` holds the MAME zips,
`ar_sprg.rom` is made by `python3 tools/arcadia_rom.py ar_sprg <romdir> ar_sprg.rom`).

| What | Result | How to repeat |
|---|---|---|
| MRAs | every MRA, assembled by the MiSTer MRA rules (`tools/mra_build.py`) from the MAME zips, byte-identical to the image `tools/arcadia_rom.py` builds from MAME's loading rules: 22 sets; the md5 in each MRA is the one Main_MiSTer computes (over each part's bytes in the MRA's order) | `python3 tools/make_mra.py <romdir>` |
| ROM loader (machine bench) | the image downloaded through `rtl/arcadia_loader.v`, the memory compared word for word with an independent C++ computation of the layout and the unscrambling: identical, 1 310 720 words each for `ar_sprg`, `ar_xeon`, `ar_argh`, `ar_fasta` (not scrambled), `ar_ninj2` (zero fill) | `sh sim/run_sys.sh ar_sprg.rom 1 out/chk -checkload` |
| Boot, Space Ranger | the whole machine in Verilator against MAME 0.289, first start with a blank NVRAM: Kickstart 1.3, the OnePlay BIOS's resident "strap" and its warm reboot, CoolCapture into the BIOS on MAME's frames (245 / 246); the program counter per frame follows MAME's; chip RAM at frames 200-300 within 9-46 bytes of MAME's (interrupt-time values); frames 275 and 300 (the OnePlay screen) identical to MAME's snapshots, 0 of 174 484 pixels differ | `sh sim/run_sys.sh ar_sprg.rom 400 out/f -snapevery 25`, `sh tools/mame_dump.sh ar_sprg out/mame "" "" 400 25`, `python3 tools/cmp_frame.py out/f_00300.ppm out/mame/snap_300.png out/cmp300` |
| Space Ranger to the title, a coin | 2 400 frames from power-on with a coin at frame 2 000 (`sim/sched_coin.txt`), every 100th frame and the ones after the coin against MAME's: frames 300-1 800 (OnePlay's NVRAM set-up, "1 Games Present", the game loading) identical; the title (1 900-2 010) identical but for the blinking "Insert coin to play" and a small animation (phase); after the coin the credit screen with "1 CREDITS" and its countdown identical at 2 050-2 400 (4 pixels at 2 050 / 2 080, 0 from 2 100) | `-sched sim/sched_coin.txt` on both |
| Space Ranger, play | 2 800 frames: a coin, start, the joystick and both buttons (`sim/sched_play.txt`), every 50th frame against MAME's: identical through the credit screen, start and the level's load (2 100-2 350); in play the same scenes and score (1 000 at 2 400, 4 000 at 2 800), the scrolling a frame apart at times (0.03-8 % of the pixels). This test found player 1 wired to the Amiga's port 1 instead of port 0 (fixed) | `-sched sim/sched_play.txt` on both |
| Aaargh (its own memory map, no BIOS) | 600 frames: the title screen identical to MAME's from frame 300 (bench 300 = MAME 297: the game starts 3 frames later), bench 450 = MAME 447 identical; from 500 the logo's colour cycle and the little dragon's animation are a step apart (phase) | as the boot, with `ar_argh.rom` |
| The MiSTer top level, loads (`sim/emu`) | `ArcadiaSystems.sv` itself with hps_io, the PLL and the SDRAM controller stubbed: the image streamed through the ioctl port (the download ending right after the last byte, as Main_MiSTer's does), or fast-loaded from a DDR3 model with 10 % of its clocks busy: the memory identical to the layout, 1 310 720 words, both ways; a fast load has the image in memory 0.39 s after it starts and the 68000 runs at 0.53 s (machine time); 0 DDR3 protocol errors. The run found the 68000 never let go when the last word was still waiting for its SDRAM slot as the download ended (fixed) | `sh sim/emu/run_emu.sh ar_sprg.rom 4 out/stream`, `FAST=1 ...` |
| The MiSTer top level, video modes (`sim/emu/run_modes.sh`) | 26 modes, each from a model saved at the OnePlay screen (frame 300 of a fast-loaded boot): Scandoubler Fx HQ2x and CRT 25 / 50 / 75 %, `forced_scandoubler` (also with HQ2x and CRT 50 %), CRT Adjust at each setting's limits and combined (and under the scandoubler, where it stays off), the five Scale modes (also with Full Screen, a 1280 x 720 scaler, HQ2x and CRT Adjust): all pass. A vertical sync every frame at 59.958 Hz (after a switch to the scandoubler two frames differ by up to 4 clocks of 114.5 MHz, then none in 36), 263 lines with 241 picture rows, 526 / 482 through the scandoubler, every row alike; the size asked of the scaler as `video_freak`'s rule gives it; the pictures dot for dot the 15 kHz run's (HQ2x 98.8 %, its interpolation). CRT Adjust at 0 gives the plain raster to the clock; H-Size +6 / -16 scale the rows by 70/64 and 48/64; H-Position +32 / -48 move them 512 / 768 clocks (cut at the line's end or the hsync pulse); V-Shift moves them by whole lines. In a whole boot (262 frames) two frames are 284 lines long, frames 104 and 250 while Kickstart and the BIOS start up (the machine's raster itself, not the video path's), the others 263 | `REBUILD=1 FAST=1 SAVEAT=300 SAVE=out/sprg300.sav sh sim/emu/run_emu.sh ar_sprg.rom 400 out/emu`, `bash sim/emu/run_modes.sh ar_sprg.rom out/sprg300.sav out/modes` |
| Button names (the MRAs' `<buttons>`) | from the games' instruction and control screens where they show them (Space Ranger, Aaargh, Ninja Mission, Blastaball, Leader Board, Fast Break, Soccer), and each button pressed on its own in MAME 0.289 against a run without it; Bowling's and Table Hockey's code reads either button; Darts never reads button 2; Sidewinder, RoadWars and Spot do nothing with it | `tools/mame_dump.sh` with a schedule pressing `b1` or `b2` |
| Quartus 17.0.2 (`releases/arcadiasystems_20261021.*`) | fits: 35 % of the ALMs (14 652), 28 % of the RAM blocks; timing met on every clock with the NTSC clock's 0.92 % as extra setup uncertainty: setup +1.146 ns at 114.5 MHz, +1.500 ns at 28.6 MHz, +5.541 ns at the 57.3 MHz video clock, +0.112 ns HDMI; holds positive. A build from a fresh clone of the repository gives the same RBF, bit for bit | `quartus_sh --flow compile ArcadiaSystems` |
| On a real MiSTer (the owner's, 2026-10-21) | the first build of release 20261021 (commit `bd0529a`): every game loads and plays. The rebuild (fast loading, CRT Adjust, Scale, the button names): not yet | `releases/arcadiasystems_20261021.rbf`, `dist/ArcadiaSystems_MiSTer_20261021.zip` |

## Bugs found on the way

* The copper never reloaded its pointer in Verilator: `agnus_copper.v`'s blocking strobes raced (`modules/VENDOR.md`).
* Player 1 was on the Amiga's game port 1: Minimig's userio takes port 0 from its `_joy2` input.
* The MRAs' md5 was the assembled image's; Main_MiSTer's is over each part's bytes in the MRA's order, and with a mismatch it
  does not send the ROM (the owner's first hardware test).
* With the loader writing the SDRAM directly, the last word could still wait for its slot when the download ended, and the
  68000 was never let go (found in the top-level bench before any build).

## Open points

* MAME finds a genlock and the core does not (Kickstart's test at `$FCB008`; README).
* The coin counters follow MAME's model; the real coin hardware is not documented.
* Leader Board Golf's 4-way joystick is not enforced.
* The board's DIP switch (DSW1 1): MAME does not say what it does.
