## Arcadia Systems for MiSTer - 20261021

The first build of the core for the **Arcadia Multi Select** (Arcadia Systems / Mastertronic, 1987-1990). The machine
is an Amiga 500 board with a ROM cage. The core is Minimig-AGA fixed to the A500 (OCS, NTSC, 68000, 512 KB chip RAM),
with the Arcadia ROM board, BIOS, NVRAM, coin and start inputs added from MAME 0.289's driver. It comes with MRAs for
the 22 working MAME 0.289 sets: 16 games, and 6 other versions in `_alternatives`.

**Not yet tested on a MiSTer.** It was checked in simulation against MAME 0.289 (below).

### Install

1. Unzip `ArcadiaSystems_MiSTer_20261021.zip` over the root of the SD card. It adds the MRAs to `_Arcade/` and
   `_Arcade/_alternatives/`, and `_Arcade/cores/arcadiasystems_20261021.rbf`.
2. Put your own MAME 0.289 zips in `games/mame/`: the game's zip and `ar_bios.zip`, which also holds the Kickstart 1.3
   ROM. Merged or split sets both work. No ROMs are included.
3. Start a game from the Arcade menu. On the first start the BIOS initialises its NVRAM ("Initializing GCP NonVolatile
   RAM"), and the game comes up after about half a minute, as on MAME. The NVRAM is saved to the SD card.

The OSD's version line reads `v261021`.

### Checked

- **ROM path:** every MRA, assembled by the MiSTer MRA rules, is byte-identical to the image `tools/arcadia_rom.py`
  builds from MAME's loading rules (22 sets). The loader's work in the simulated machine (download, address map,
  unscrambling) equals an independent computation, word for word, for five sets that cover every case.
- **The machine against MAME 0.289** (Verilator, the whole machine with the SDRAM controller's timing):
  - **Space Ranger:** from power-on with a blank NVRAM, through Kickstart and the OnePlay BIOS's set-up, the game's
    load and title, a coin and the credit screen, every frame checked is pixel-identical to MAME's. The only exceptions
    are a blink and an animation phase on the title.
  - **Aaargh** (its own memory map, no BIOS): the title screen is identical, starting 3 frames after MAME's.
- **Timing:** met on every clock, with the NTSC clock's 0.92 % on top: worst setup slack +1.239 ns at 114.5 MHz,
  +1.649 ns at 28.6 MHz, +5.081 ns at the 57.3 MHz video clock, +0.423 ns HDMI; holds positive. 34 % of the ALMs, 26 %
  of the RAM blocks.

### Controls

Two players, each with a joystick and two buttons, plus start, coin and service. On the keyboard: 1 / 2 start, 5 / 6
coin, F2 service. OSD: the BIOS's DIP switch (DSW1 1), the A500 audio filter, stereo mix, and NVRAM save.

### Known differences

- MAME's Kickstart finds a genlock (its beam counter does not stop on BPLCON0's external sync). The core's does not, as
  on a real A500. The picture is the same.
- Leader Board Golf's 4-way joystick is not enforced.

### Credits

Minimig (Dennis van Weeren and the Minimig-AGA / MiSTer contributors), fx68k (Jorge Cwik), MAME's Arcadia driver
(Ernesto Corvi, Mariusz Wojcieszek).
