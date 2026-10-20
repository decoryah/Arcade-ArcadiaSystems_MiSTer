# Arcadia Systems for MiSTer

A MiSTer core for the Arcadia Multi Select arcade system (Arcadia Systems / Mastertronic, 1987-1990). The machine is an
Amiga 500 board with a ROM cage on the expansion port, so the core is built on
[Minimig-AGA_MiSTer](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer), fixed to the A500 / OCS / NTSC configuration,
with the Arcadia ROM board, BIOS, NVRAM, coin and start inputs added. It is written from MAME 0.289's driver
(`src/mame/amiga/arsystems.cpp`). No ROMs are in this repository.

**Status.** Work in progress, not yet tested on a MiSTer. In simulation the core boots like MAME through Kickstart 1.3 and the
OnePlay BIOS (see "What is verified").

## Install

Copy `releases/arcadiasystems_<date>.rbf` to `_Arcade/cores/` and the `.mra` files to `_Arcade/` (the `_alternatives` folder
too, if you want the other versions). The MAME 0.289 zips go in `games/mame/`: the game's zip and `ar_bios.zip`, which also
holds the Kickstart 1.3 ROM, so no separate Kickstart file is needed. Merged or split sets both work.

| MRA | MAME set |
|---|---|
| Aaargh (Arcadia) | `ar_argh` |
| Blastaball (Arcadia, V 2.1) | `ar_blast` |
| Delta Command (Arcadia) | `ar_dlta` |
| Leader Board Golf (Arcadia, set 1, V 2.5) | `ar_ldrb` (also `ar_ldrba`, `ar_ldrbb`) |
| Magic Johnson's Fast Break (Arcadia, V 2.8) | `ar_fast` (also `ar_fasta`) |
| Ninja Mission (Arcadia, set 1, V 2.5) | `ar_ninj` (also `ar_ninj2`) |
| Pharaohs Match (Arcadia) | `ar_pm` |
| RoadWars (Arcadia, V 2.3) | `ar_rdwr` |
| Sidewinder (Arcadia, set 1, V 2.1) | `ar_sdwr` (also `ar_sdwr2`) |
| Space Ranger (Arcadia, V 2.0) | `ar_sprg` |
| SportTime Bowling (Arcadia, V 2.1) | `ar_bowl` |
| SportTime Table Hockey (Arcadia, set 1, V 2.1) | `ar_airh` (also `ar_airh2`) |
| Spot (Arcadia, V 2.0) | `ar_spot` |
| World Darts (Arcadia, set 1, V 2.1) | `ar_dart` |
| World Trophy Soccer (Arcadia, V 3.0) | `ar_socc` |
| Xenon (Arcadia, V 2.3) | `ar_xeon` |

`ar_dart2` has no MRA: its dump is bad and MAME marks it not working.

The first start of a game initialises the BIOS's NVRAM ("Initializing GCP NonVolatile RAM") and takes about half a minute to
reach the game, as on MAME. The NVRAM is saved to the SD card (`<nvram>` in the MRA; the file is MAME's `nvram` file).

## Controls and OSD

Two players, each with a joystick and two buttons, plus start, coin and service. On the keyboard: 1 / 2 start, 5 / 6 coin,
F2 service (MAME's keys). Player 1 is the Amiga's game port 0 and player 2 port 1, as in MAME.

| OSD option | |
|---|---|
| Aspect ratio, Scandoubler Fx, Scale | the usual video options |
| Audio filter | A500 (follows the power LED, as the real filter), Off, On |
| Stereo mix | Paula's hard left / right channels mixed 0-100 % |
| DSW1 1 | the board's DIP switch, Reset (default) or Set |
| Autosave NVRAM, Save NVRAM | write the NVRAM when the OSD opens after a change, or now |

Service mode: hold service when the BIOS has printed "INITIALIZATION OK", or press it during a game.

## What is verified

| check | method | result |
|---|---|---|
| MRAs | every MRA assembled from the MAME zips (`tools/make_mra.py <romdir>`) and compared with `tools/arcadia_rom.py` | identical, 22 sets |
| ROM loader | the image downloaded through `rtl/arcadia_loader.v` in the simulation, the memory compared word for word with an independent C++ computation of the layout and unscrambling (`sim/run_sys.sh ... -checkload`) | identical, 1 310 720 words each for `ar_sprg`, `ar_xeon`, `ar_argh`, `ar_fasta` (not scrambled), `ar_ninj2` (zero fill) |
| Aaargh (own memory map, no BIOS) | as below, 600 frames | the title screen identical to MAME's from frame 300 (sim 300 = MAME 297: the game starts 3 frames later), sim 450 = MAME 447 identical; from 500 the logo's colour cycle and the little dragon's animation are a step apart (phase) |
| Space Ranger to the title, a coin | 2 400 frames from power-on (blank NVRAM) with a coin at frame 2 000 (`sim/sched_coin.txt`), every 100th frame and the ones after the coin against MAME's | frames 300-1 800 (OnePlay's NVRAM set-up, "1 Games Present", the game loading) identical; the title (1 900-2 010) identical but for the blinking "Insert coin to play" and a small animation (phase); after the coin, the credit screen with "1 CREDITS" and its countdown identical at 2 050-2 400 (4 pixels at 2 050 / 2 080, 0 from 2 100) |
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
| `rtl/arcadia_loader.v` | the MRA image to the machine's memory over Minimig's host bus, unscrambling the ROMs |
| `modules/minimig/` | Minimig-AGA, vendored (`modules/VENDOR.md`: the commit and the local changes) |
| `sys/` | the MiSTer framework |
| `mra/` | MRA files (written by `tools/make_mra.py`) |
| `docs/hardware.md` | the hardware as MAME describes it, and how the core maps it |
| `tools/` | sets table (`gen_sets.py` -> `arcadia_sets.py`), ROM image (`arcadia_rom.py`), MRAs (`make_mra.py`, `mra_build.py`), MAME captures (`mame_dump.sh`, `lua/`), frame comparison (`cmp_frame.py`) |
| `sim/` | the Verilator bench of the whole machine |

## Building

Quartus Prime 17.0 (Lite is enough): open `ArcadiaSystems.qpf` and compile, or `quartus_sh --flow compile ArcadiaSystems`.

The simulation runs in WSL with Verilator 5:

```bash
python3 tools/arcadia_rom.py ar_sprg <romdir> ar_sprg.rom
sh sim/run_sys.sh $PWD/ar_sprg.rom 400 $PWD/out/f -snapevery 25
sh tools/mame_dump.sh ar_sprg out/mame "" "" 400 25
python3 tools/cmp_frame.py out/f_00300.ppm out/mame/snap_300.png out/cmp300
```

## Credits

* Minimig: Dennis van Weeren, with the Minimig-AGA and MiSTer work of Jakub Bednarski, Sascha Boing, Rok Krajnc,
  Alastair M. Robinson, Alexey Melnikov (Sorgelig) and the other contributors named in the sources.
* fx68k: Jorge Cwik.
* MAME's Arcadia driver: Ernesto Corvi and Mariusz Wojcieszek.
* `tools/mra_build.py`: from plasticbugs/analogue-pocket-gaiapolis (GPL-3.0).

## Licence

GPL-3.0 (see `LICENSE`). The vendored modules keep their own licences.
