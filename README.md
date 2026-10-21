# Arcadia Systems for MiSTer

A MiSTer core for the Arcadia Multi Select arcade system (Arcadia Systems / Mastertronic, 1987-1990). The machine is an
Amiga 500 board with a ROM cage on the expansion port, so the core is built on
[Minimig-AGA_MiSTer](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer), fixed to the A500 / OCS / NTSC configuration,
with the Arcadia ROM board, BIOS, NVRAM, coin and start inputs added. It is written from MAME 0.289's driver
(`src/mame/amiga/arsystems.cpp`). No ROMs are in this repository.

**Status.** `releases/arcadiasystems_20261021.rbf`. The repository owner has tested it on a MiSTer: all games work. In
simulation it runs like MAME 0.289 through Kickstart 1.3, the OnePlay BIOS, a game's load, title, coin and credit screen and
play (see "What is verified"). Fast loading, CRT Adjust, the five Scale modes and the games' own button names came after that
test; they are verified in simulation on the whole MiSTer top level.

## Install

Copy `releases/arcadiasystems_<date>.rbf` to `_Arcade/cores/` and the `.mra` files to `_Arcade/` (the `_alternatives` folder
too, if you want the other versions). The MAME 0.289 zips go in `games/mame/`: the game's zip and `ar_bios.zip`, which also
holds the Kickstart 1.3 ROM, so no separate Kickstart file is needed. Merged or split sets both work.

The MRAs ask for fast loading (`address=` on the ROM): a Main_MiSTer that supports it puts the assembled 2.5 MB image in the DDR3
in one go and the core reads it from there; an older one sends it the usual way. Either way the core writes the image straight
into its SDRAM, a word in each 7 MHz slot.

| MRA | MAME set | Button 1 | Button 2 |
|---|---|---|---|
| Aaargh (Arcadia) | `ar_argh` | Fire | Punch |
| Blastaball (Arcadia, V 2.1) | `ar_blast` | Fire | Accelerate |
| Delta Command (Arcadia) | `ar_dlta` | Fire | Special Weapon |
| Leader Board Golf (Arcadia, set 1, V 2.5) | `ar_ldrb` (also `ar_ldrba`, `ar_ldrbb`) | Select Club | Top View |
| Magic Johnson's Fast Break (Arcadia, V 2.8) | `ar_fast` (also `ar_fasta`) | Shoot / Jump | Pass / Switch |
| Ninja Mission (Arcadia, set 1, V 2.5) | `ar_ninj` (also `ar_ninj2`) | Punch / Kick | Sword |
| Pharaohs Match (Arcadia) | `ar_pm` | Select | Cancel |
| RoadWars (Arcadia, V 2.3) | `ar_rdwr` | Fire | - |
| Sidewinder (Arcadia, set 1, V 2.1) | `ar_sdwr` (also `ar_sdwr2`) | Fire | - |
| Space Ranger (Arcadia, V 2.0) | `ar_sprg` | Fire | Net |
| SportTime Bowling (Arcadia, V 2.1) | `ar_bowl` | Throw | Throw |
| SportTime Table Hockey (Arcadia, set 1, V 2.1) | `ar_airh` (also `ar_airh2`) | Speed Up | Speed Up |
| Spot (Arcadia, V 2.0) | `ar_spot` | Select | - |
| World Darts (Arcadia, set 1, V 2.1) | `ar_dart` | Throw | - |
| World Trophy Soccer (Arcadia, V 3.0) | `ar_socc` | Kick | Switch Player |
| Xenon (Arcadia, V 2.3) | `ar_xeon` | Fire | Transform |

The button names are the games' own, from their instruction and control screens where they have them, and from play in MAME
0.289 (`tools/make_mra.py`); "-" is a button the game does not use. Leader Board swings with the joystick alone. Bowling and
Table Hockey take either button.

`ar_dart2` has no MRA: its dump is bad and MAME marks it not working.

The first start of a game initialises the BIOS's NVRAM ("Initializing GCP NonVolatile RAM") and takes about half a minute to
reach the game, as on MAME. The NVRAM is saved to the SD card (`<nvram>` in the MRA; the file is MAME's `nvram` file).

## Controls and OSD

Two players, each with a joystick and two buttons (named per game, above), plus start and coin. On the keyboard: 1 / 2 start,
5 / 6 coin, F2 service (MAME's keys); service is on the keyboard only, so a pad cannot enter the BIOS's service mode by
accident. Player 1 is the Amiga's game port 0 and player 2 port 1, as in MAME.

| OSD option | |
|---|---|
| Aspect ratio | Original (4:3), Full Screen, the MiSTer.ini's custom ratios |
| Scale | the HDMI scaler: Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+ |
| Scandoubler Fx | None (15 kHz), or 31 kHz with HQ2x or CRT scanlines 25 / 50 / 75 % |
| CRT Adjust (page) | for a 15 kHz CRT: H-Size (+6 .. -16, 1/64 of a dot a step), H-Position (+32 .. -48 lores dots), V-Shift (+15 .. -16 lines). The picture moves through a line buffer (rmonic79's MiSTer-CRT-Adjust); the sync pulses stay where they are, so the monitor keeps its lock. HDMI follows it; it is off while the scandoubler is in use |
| Audio filter | A500 (follows the power LED, as the real filter), Off, On |
| Stereo mix | Paula's hard left / right channels mixed 0-100 % |
| DSW1 1 | the board's DIP switch, Reset (default) or Set |
| Autosave NVRAM, Save NVRAM | write the NVRAM when the OSD opens after a change, or now |

Service mode: hold service when the BIOS has printed "INITIALIZATION OK", or press it during a game.

## What is verified

| check | method | result |
|---|---|---|
| timing | Quartus 17.0, seed 1 (`releases/*.sta.summary`); the PLL is built for PAL and runs at NTSC, so the setup checks carry the 0.92 % as extra uncertainty | met on every clock: setup +1.146 ns at 114.5 MHz, +1.500 ns at 28.6 MHz, +5.541 ns at the 57.3 MHz video clock, +0.112 ns HDMI; holds positive. 35 % of the ALMs, 28 % of the RAM blocks |
| MRAs | every MRA assembled from the MAME zips (`tools/make_mra.py <romdir>`) and compared with `tools/arcadia_rom.py` | identical, 22 sets |
| the MiSTer top level | `ArcadiaSystems.sv` whole in Verilator (`sim/emu`): hps_io, the PLL and the SDRAM controller stubbed, the framework's `video_mixer` (scandoubler, HQ2x) and `video_freak` real; the image streamed through the ioctl port, or fast-loaded through a DDR3 model | both loads leave the memory identical to the layout, 1 310 720 words; a fast load has the image in memory 0.39 s after it starts (machine time). 26 video modes, each from the OnePlay screen: Scandoubler Fx (HQ2x, CRT 25 / 50 / 75 %), `forced_scandoubler` (also with HQ2x and CRT 50 %), CRT Adjust at each setting's limits and combined (and under the scandoubler, where it stays off), the five Scale modes (also with Full Screen, a 1280 x 720 scaler, HQ2x and CRT Adjust): all pass. A vertical sync every frame at 59.958 Hz (after a switch to the scandoubler two frames differ by up to 4 clocks of 114.5 MHz, then none in 36), 263 lines with 241 picture rows, 526 / 482 through the scandoubler, every row alike, the size asked of the scaler as `video_freak`'s rule gives it; the pictures dot for dot the 15 kHz run's (HQ2x 98.8 %, its interpolation). CRT Adjust at 0 gives the plain raster to the clock; H-Size +6 / -16 scale the rows by 70/64 and 48/64, H-Position +32 / -48 move them 512 / 768 clocks (cut at the line's end or the hsync pulse), V-Shift moves them by whole lines |
| ROM loader | the image downloaded through `rtl/arcadia_loader.v` in the simulation, the memory compared word for word with an independent C++ computation of the layout and unscrambling (`sim/run_sys.sh ... -checkload`) | identical, 1 310 720 words each for `ar_sprg`, `ar_xeon`, `ar_argh`, `ar_fasta` (not scrambled), `ar_ninj2` (zero fill) |
| Aaargh (own memory map, no BIOS) | as below, 600 frames | the title screen identical to MAME's from frame 300 (sim 300 = MAME 297: the game starts 3 frames later), sim 450 = MAME 447 identical; from 500 the logo's colour cycle and the little dragon's animation are a step apart (phase) |
| Space Ranger to the title, a coin | 2 400 frames from power-on (blank NVRAM) with a coin at frame 2 000 (`sim/sched_coin.txt`), every 100th frame and the ones after the coin against MAME's | frames 300-1 800 (OnePlay's NVRAM set-up, "1 Games Present", the game loading) identical; the title (1 900-2 010) identical but for the blinking "Insert coin to play" and a small animation (phase); after the coin, the credit screen with "1 CREDITS" and its countdown identical at 2 050-2 400 (4 pixels at 2 050 / 2 080, 0 from 2 100) |
| Space Ranger, play | 2 800 frames: a coin, start, then the joystick and both buttons (`sim/sched_play.txt`), every 50th frame against MAME's | identical through the credit screen, start and the level's load (2 100-2 350); in play the same scenes and score (1 000 at 2 400, 4 000 at 2 800), the scrolling a frame apart at times (0.03-8 % of the pixels; 56 pixels at 2 800). This test found player 1 wired to the Amiga's port 1 instead of port 0 (fixed) |
| boot, Space Ranger | the whole machine in Verilator (`sim/run_sys.sh`) against MAME 0.289 (`tools/mame_dump.sh`), first start with blank NVRAM | Kickstart 1.3, the OnePlay BIOS's resident "strap" and its warm reboot, CoolCapture into the BIOS at the same frames as MAME (245 / 246); the program counter per frame follows MAME's; chip RAM at frames 200-300 within 9-46 bytes of MAME's (interrupt-time values); frames 275 and 300 (the OnePlay screen) identical to MAME's snapshots, 0 of 174 484 pixels differ |

## Known differences / open points

* MAME finds a genlock and the core does not. Kickstart's test (`$FCB008`) sets BPLCON0's external sync and checks
  whether the beam counter stops. It does on a real A500 and in Minimig, but not in MAME, so MAME's copper lists carry
  `$0102` in BPLCON0 (genlock audio and external sync). The core's lists carry `$0200`, as a real Arcadia's would. The
  picture is the same; chip RAM differs in those words.

* The coin counters follow MAME's model (two 2-bit counters taken down by port B writes); the real coin hardware is not
  documented.
* Leader Board Golf's 4-way joystick is not enforced (MAME's `PORT_4WAY`).
* MAME keeps the ROM board switch across a soft reset; the core resets it to "in".

## Repository layout

| path | contents |
|---|---|
| `ArcadiaSystems.sv` | the MiSTer top level (derived from Minimig's `Minimig.sv`) |
| `rtl/arcadia_amiga.v` | the A500 (derived from Minimig's `minimig.v`) with the Arcadia board |
| `rtl/arcadia_board.v` | NVRAM, the ROM board switch, the coin counters and CIA-A port B |
| `rtl/arcadia_loader.v` | the MRA image to the machine's memory, straight into the SDRAM controller, unscrambling the ROMs |
| `rtl/arcadia_fastload.v` | fast loading: the image from the DDR3 to the loader |
| `rtl/arcadia_video.sv` | the video path: Minimig's, with CRT Adjust and the Scale modes |
| `modules/crt-adjust/` | rmonic79's MiSTer-CRT-Adjust, vendored |
| `modules/minimig/` | Minimig-AGA, vendored (`modules/VENDOR.md`: the commit and the local changes) |
| `sys/` | the MiSTer framework |
| `mra/` | MRA files (written by `tools/make_mra.py`) |
| `docs/hardware.md` | the hardware as MAME describes it, and how the core maps it |
| `tools/` | sets table (`gen_sets.py` -> `arcadia_sets.py`), ROM image (`arcadia_rom.py`), MRAs (`make_mra.py`, `mra_build.py`), MAME captures (`mame_dump.sh`, `lua/`), frame comparison (`cmp_frame.py`) |
| `sim/` | the Verilator bench of the whole machine (`run_sys.sh`), and of the MiSTer top level (`emu/run_emu.sh`, `emu/run_modes.sh`) |

## Building

Quartus Prime 17.0 (Lite is enough): open `ArcadiaSystems.qpf` and compile, or `quartus_sh --flow compile ArcadiaSystems`.

The simulation runs in WSL with Verilator 5:

```bash
python3 tools/arcadia_rom.py ar_sprg <romdir> ar_sprg.rom
sh sim/run_sys.sh $PWD/ar_sprg.rom 400 $PWD/out/f -snapevery 25
sh tools/mame_dump.sh ar_sprg out/mame "" "" 400 25
python3 tools/cmp_frame.py out/f_00300.ppm out/mame/snap_300.png out/cmp300
```

The MiSTer top level (`sim/emu`): a fast load, the memory checked, the model saved at the OnePlay screen, then the video modes
from there:

```bash
REBUILD=1 FAST=1 SAVEAT=300 SAVE=$PWD/out/sprg300.sav sh sim/emu/run_emu.sh $PWD/ar_sprg.rom 400 $PWD/out/emu
bash sim/emu/run_modes.sh $PWD/ar_sprg.rom $PWD/out/sprg300.sav $PWD/out/modes
```

## Credits

* Minimig: Dennis van Weeren, with the Minimig-AGA and MiSTer work of Jakub Bednarski, Sascha Boing, Rok Krajnc,
  Alastair M. Robinson, Alexey Melnikov (Sorgelig) and the other contributors named in the sources.
* fx68k: Jorge Cwik.
* MAME's Arcadia driver: Ernesto Corvi and Mariusz Wojcieszek.
* CRT Adjust: rmonic79 (Umberto Parisi), with Andrea Bogazzi (asturur).
* `tools/mra_build.py`: from plasticbugs/analogue-pocket-gaiapolis (GPL-3.0).

## Licence

GPL-3.0 (see `LICENSE`). The vendored modules keep their own licences.
