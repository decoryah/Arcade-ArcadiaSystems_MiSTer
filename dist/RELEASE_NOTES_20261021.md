## Arcadia Systems for MiSTer - 20261021

A core for the **Arcadia Multi Select** (Arcadia Systems / Mastertronic, 1987-1990). The machine is an Amiga 500 board
with a ROM cage. The core is Minimig-AGA fixed to the A500 (OCS, NTSC, 68000, 512 KB chip RAM), with the Arcadia ROM
board, BIOS, NVRAM, coin and start inputs added from MAME 0.289's driver. It comes with MRAs for the 22 working MAME
0.289 sets: 16 games, and 6 other versions in `_alternatives`.

The first build of this release was tested on a MiSTer by the repository owner: all games work. This rebuild adds:

- **Fast loading.** The MRAs carry `address=` on the ROM image: a Main_MiSTer that supports it puts the 2.5 MB image
  in the DDR3 in one go, and the core reads it from there. The loader also writes straight into the SDRAM now, a word
  in each 7 MHz slot, instead of over the 68000's bus: the image is in memory in 0.39 s of machine time from the DDR3
  (it took 1.1 s before), and a streamed load is no longer slowed down by the core.
- **CRT Adjust** (rmonic79's MiSTer-CRT-Adjust), an OSD page for 15 kHz CRTs: H-Size, H-Position and V-Shift. The
  sync pulses stay put, so the monitor keeps its lock.
- **Scale** with the five modes: Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+.
- **The games' own button names** (below), from their instruction and control screens and from play in MAME.
- **Service** is on the keyboard only (F2), no longer in the pad mapping.
- The scandoubler (HQ2x, the CRT filters, MiSTer.ini's `forced_scandoubler`) checked on the whole top level: a
  vertical sync every frame, 526 lines of which 482 carry the picture, the picture the same as at 15 kHz.

### Install

1. Unzip `ArcadiaSystems_MiSTer_20261021.zip` over the root of the SD card. It adds the MRAs to `_Arcade/` and
   `_Arcade/_alternatives/`, and `_Arcade/cores/arcadiasystems_20261021.rbf` (it replaces the first build's).
2. Put your own MAME 0.289 zips in `games/mame/`: the game's zip and `ar_bios.zip`, which also holds the Kickstart 1.3
   ROM. Merged or split sets both work. No ROMs are included.
3. Start a game from the Arcade menu. On the first start the BIOS initialises its NVRAM ("Initializing GCP NonVolatile
   RAM"), and the game comes up after about half a minute, as on MAME. The NVRAM is saved to the SD card.

The OSD's version line reads `v261021`.

### Buttons

| game | Button 1 | Button 2 |
|---|---|---|
| Aaargh | Fire | Punch |
| Blastaball | Fire | Accelerate |
| Delta Command | Fire | Special Weapon |
| Leader Board Golf | Select Club | Top View |
| Magic Johnson's Fast Break | Shoot / Jump | Pass / Switch |
| Ninja Mission | Punch / Kick | Sword |
| Pharaohs Match | Select | Cancel |
| RoadWars | Fire | - |
| Sidewinder | Fire | - |
| Space Ranger | Fire | Net |
| SportTime Bowling | Throw | Throw |
| SportTime Table Hockey | Speed Up | Speed Up |
| Spot | Select | - |
| World Darts | Throw | - |
| World Trophy Soccer | Kick | Switch Player |
| Xenon | Fire | Transform |

"-": the game does not use the button. Leader Board swings with the joystick alone; Bowling and Table Hockey take either
button. Start and coin are Start and Select on a pad; on the keyboard 1 / 2 start, 5 / 6 coin, F2 service.

### Checked

- **ROM path:** every MRA, assembled by the MiSTer MRA rules, is byte-identical to the image `tools/arcadia_rom.py`
  builds from MAME's loading rules (22 sets). In the simulated top level a streamed load and a fast load each leave the
  memory identical to an independent computation of the layout and unscrambling, word for word.
- **The machine against MAME 0.289** (Verilator, the whole machine with the SDRAM controller's timing): Space Ranger from
  power-on through Kickstart, the OnePlay BIOS, the game's load and title, coin, credit screen and play; Aaargh's title.
- **Video modes** (the whole MiSTer top level with the framework's video_mixer and video_freak): 26 modes from the OnePlay screen, all passing: Scandoubler Fx
  (HQ2x, CRT 25 / 50 / 75 %), `forced_scandoubler`, CRT Adjust at each setting's limits, the five Scale modes. A
  vertical sync every frame at 59.958 Hz; 263 lines with 241 picture rows, 526 / 482 through the scandoubler; the
  pictures dot for dot the 15 kHz ones (HQ2x but for its interpolation); the size asked of the HDMI scaler as the
  framework's rule gives it.
- **Timing:** met on every clock, with the NTSC clock's 0.92 % on top: worst setup slack +1.146 ns at 114.5 MHz,
  +1.500 ns at 28.6 MHz, +5.541 ns at the 57.3 MHz video clock, +0.112 ns HDMI; holds positive. 35 % of the ALMs, 28 %
  of the RAM blocks.

### Known differences

- MAME's Kickstart finds a genlock (its beam counter does not stop on BPLCON0's external sync). The core's does not, as
  on a real A500. The picture is the same.
- Leader Board Golf's 4-way joystick is not enforced.

### Credits

Minimig (Dennis van Weeren and the Minimig-AGA / MiSTer contributors), fx68k (Jorge Cwik), MAME's Arcadia driver
(Ernesto Corvi, Mariusz Wojcieszek), CRT Adjust (rmonic79 / Umberto Parisi, with Andrea Bogazzi).
