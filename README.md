# Arcadia Systems for MiSTer

A MiSTer core for the Arcadia Multi Select arcade system (Arcadia Systems / Mastertronic, 1987-1990). The machine is an
Amiga 500 board with a ROM cage on the expansion port, so the core is built on
[Minimig-AGA_MiSTer](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer), fixed to the A500 / OCS / NTSC configuration,
with the Arcadia ROM board, BIOS, NVRAM, coin and start inputs added. It is written from MAME 0.289's driver
(`src/mame/amiga/arsystems.cpp`). No ROMs are in this repository.

**Status.** Work in progress. The repository holds the vendored Minimig and MiSTer framework and the hardware notes
(`docs/hardware.md`); the Arcadia top level, ROM loader and MRAs are being written. Not yet tested on a MiSTer.

## Games

The 24 sets in MAME 0.289 (`ar_bios` plus the games), listed in `docs/hardware.md`. Each needs MAME's `ar_bios.zip`,
which also carries the Kickstart 1.3 ROM, so no separate Kickstart file is needed.

## Repository layout

| path | contents |
|---|---|
| `rtl/` | the Arcadia parts: top-level glue, ROM loader, ROM board and NVRAM decode, inputs |
| `modules/minimig/` | Minimig-AGA, vendored (see `modules/VENDOR.md` for the commit and the local changes) |
| `sys/` | the MiSTer framework |
| `mra/` | MRA files |
| `docs/hardware.md` | the hardware as MAME describes it, and how the core maps it |
| `tools/`, `sim/` | MRA generation, MAME comparison and simulation |
| `releases/` | built cores |

## Credits

* Minimig: Dennis van Weeren, with the Minimig-AGA and MiSTer work by Jakub Bednarski, Sascha Boing, Rok Krajnc,
  Alastair M. Robinson, Sorgelig and the other contributors named in the sources.
* fx68k: Jorge Cwik.
* MAME's Arcadia driver: Ernesto Corvi and Mariusz Wojcieszek.

## Licence

GPL-3.0 (see `LICENSE`). The vendored modules keep their own licences.
