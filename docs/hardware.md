# Arcadia Systems hardware

The Arcadia Multi Select (Arcadia Systems / Mastertronic, 1987-1990) is an Amiga 500 main board with a ROM cage on the
side expansion port. This file describes the hardware as MAME 0.289 emulates it (`src/mame/amiga/arsystems.cpp`, on top
of `amiga.cpp` / `amiga_m.cpp`), then how the core maps it onto Minimig. MAME 0.289 is the reference for everything here.

## 1. Machine

| part | MAME | notes |
|---|---|---|
| CPU | MC68000 at 7.159 MHz (28.636 MHz / 4, NTSC) | |
| Agnus | ID $30 (`AGNUS_HR_NTSC`, 8372 "HR" Agnus, NTSC) | the copper runs in OCS mode (`set_ecs_mode(false)`) and the register map is `ocs_map` |
| Denise | OCS (no DENISEID register) | |
| Paula | 8364, C1 = 3.58 MHz | stereo: channels 0+3 left, 1+2 right |
| CIAs | two 8520s, E clock = 7M / 10 | |
| chip RAM | 512 KB | no slow RAM, no fast RAM |
| floppy | Paula FDC present, no drive used | |
| video | NTSC timing | |
| NVRAM | battery-backed, zero on first boot (`DEFAULT_ALL_0`) | DS1220Y (2 KB) on the ROM board, mapped as a 16 KB window |

## 2. Memory map

`arcadia_map` (all games except Aaargh):

| range | contents |
|---|---|
| $000000-$1FFFFF | chip RAM 512 KB, mirrored; Kickstart overlaid at $000000 after reset (OVL) as on any A500 |
| $800000-$97FFFF | ROM board, 1.5 MB (region `user3`); unmapped after a non-zero write to $9FFFFE (reads $FFFF) |
| $980000-$9FBFFF | BIOS (region `user2`, first $7C000 bytes) |
| $9FC000-$9FFFFD | NVRAM |
| $9FFFFE | write only: 0 = ROM board in, non-zero = ROM board out (`arcadia_multibios_change_game`) |
| $A00000-$BFFFFF | CIAs |
| $C00000-$D7FFFF, $DE0000-$DFFFFF | custom chips (no slow RAM) |
| $E00000-$E7FFFF | Kickstart mirror (read) |
| $F00000-$F7FFFF | BIOS (region `user2`) again |
| $F80000-$FFFFFF | Kickstart 1.3, 256 KB mirrored to 512 KB |

Unmapped reads return $FFFF (`unmap_value_high`).

The BIOS at $F00000 is how the system takes over the boot: Kickstart 1.3 looks at $F00000 both for the $1111
diagnostic-ROM magic and for resident tags ($4AFC; the TenPlay BIOS starts with one). Which one OnePlay uses is still to
be checked against MAME.

`argh_map` (Aaargh, `ar_argh`) has no BIOS:

| range | contents |
|---|---|
| $800000-$97FFFF | ROM board (`user3`), always in (no $9FFFFE register) |
| $9FF000-$9FFFFF | NVRAM, 4 KB |
| $F00000-$F7FFFF | ROM board again (first 512 KB of `user3`) |

## 3. ROMs

Every set carries the BIOS (`ARCADIA_BIOS`, i.e. `ar_bios.zip`):

* `kickstart`: `315093-01.u2`, Kickstart 1.3, 256 KB, big-endian word order, copied to fill 512 KB.
* `user2`: the BIOS, as byte pairs (`-hi` at even addresses, `-lo` at odd). MAME's default is OnePlay 3.00
  (`scpa_01-hi_v3.0.u12` / `scpa_01-lo_v3.0.u16`, 64 KB each). The other choices are OnePlay 2.20 and 2.11, and TenPlay
  2.11, 3.11 and 4.00 (TenPlay is 256 KB in three or two pairs).
* `user3`: the game, up to 1.5 MB, as `-hi`/`-lo` 64 KB pairs at $20000 steps. Most sets fill the unused part with $FF
  (`ROMREGION_ERASEFF`). `ar_dart2`, `ar_ninj`, `ar_rdwr` and `ar_sdwr2` leave it at $00.

### Encryption

Only the low byte of each word in the first 128 KB of a region is scrambled, which is the first `-lo` chip. The fix is
a bit permutation of that byte:

```
plain[7:0] = { enc[b7], enc[b6], enc[b5], enc[b4], enc[b3], enc[b2], enc[b1], enc[b0] }
```

| set(s) | b7..b0 |
|---|---|
| OnePlay BIOS (`user2`; only if the first word is not $4AFC, so TenPlay is plain) | 6 1 0 2 3 4 5 7 |
| `ar_airh`, `ar_airh2`, `ar_argh` | 5 0 2 4 7 6 1 3 |
| `ar_bowl` | 7 6 0 1 2 3 4 5 |
| `ar_blast`, `ar_dlta` | 4 1 7 6 2 0 3 5 |
| `ar_dart`, `ar_dart2` | 4 0 7 6 3 1 2 5 |
| `ar_ldrb` | 2 3 4 1 0 7 5 6 |
| `ar_ninj`, `ar_ninj2` | 1 6 5 7 4 2 0 3 |
| `ar_rdwr` | 3 1 6 4 0 5 2 7 |
| `ar_sdwr`, `ar_sdwr2` | 6 3 4 5 2 1 0 7 |
| `ar_socc` | 0 7 1 6 5 4 3 2 |
| `ar_sprg` | 4 7 3 0 6 5 2 1 |
| `ar_xeon` | 3 1 2 4 0 5 6 7 |
| `ar_pm` | 7 6 5 4 3 2 1 0 (none) |
| `ar_fast`, `ar_fasta`, `ar_ldrba`, `ar_ldrbb`, `ar_spot` | not scrambled (`init_arcadia`) |

### Sets in MAME 0.289

| set | game | notes |
|---|---|---|
| `ar_bios` | Arcadia System BIOS | BIOS root |
| `ar_airh`, `ar_airh2` | SportTime Table Hockey | |
| `ar_blast` | Blastaball | |
| `ar_bowl` | SportTime Bowling | |
| `ar_dart`, `ar_dart2` | World Darts | `ar_dart2` is a bad dump, not working in MAME |
| `ar_dlta` | Delta Command | |
| `ar_fast`, `ar_fasta` | Magic Johnson's Fast Break | |
| `ar_ldrb`, `ar_ldrba`, `ar_ldrbb` | Leader Board Golf | 4-way joysticks |
| `ar_ninj`, `ar_ninj2` | Ninja Mission | |
| `ar_pm` | Pharaohs Match | |
| `ar_rdwr` | RoadWars | |
| `ar_sdwr`, `ar_sdwr2` | Sidewinder | |
| `ar_socc` | World Trophy Soccer | |
| `ar_spot` | Spot | |
| `ar_sprg` | Space Ranger | |
| `ar_xeon` | Xenon | |
| `ar_argh` | Aaargh | own memory map, no BIOS |

## 4. Inputs

| signal | where | MAME input |
|---|---|---|
| CIA-A PA6 (/FIR0) | game port 0 fire | P1 button 1, active low |
| CIA-A PA7 (/FIR1) | game port 1 fire | P2 button 1, active low |
| JOY0DAT | game port 0 (the A500's mouse port) | P1 joystick |
| JOY1DAT | game port 1 | P2 joystick |
| POTGO bit 10 (DATLY) | port 0 pin 9 | P1 button 2, active low |
| POTGO bit 14 (DATRY) | port 1 pin 9 | P2 button 2, active low |
| CIA-A PB0 (read) | parallel port D0 | DIP "DSW1 1": 1 = Reset (default), 0 = Set |
| CIA-A PB1 | D1 | service, active low (F2 in MAME) |
| CIA-A PB2 | D2 | start 2, active low |
| CIA-A PB3 | D3 | start 1, active low |
| CIA-A PB5:4 | D5:4 | coin 1 counter, 0-3 |
| CIA-A PB7:6 | D7:6 | coin 2 counter, 0-3 |

Coins: a rising edge on a coin input adds one to that coin's 2-bit counter (it stops at 3). A write to CIA-A port B with
bit 0 clear takes one away, from coin 1 if it is non-zero and from coin 2 otherwise. Reset clears both.

Service mode: hold service before pressing a button after the "INITIALIZATION OK" message, or press it during a game.

## 5. The core

The core is Minimig-AGA (vendored in `modules/minimig`, see `modules/VENDOR.md`) fixed to the Arcadia configuration.

| | Minimig on MiSTer | this core |
|---|---|---|
| configuration | sent by the HPS (`userio.v` UIO commands 3, 4, 5, ...) | constants: OCS, NTSC, 68000, 512 KB chip, no slow / fast RAM, no HDD, no floppy |
| Kickstart | uploaded by the HPS over the UIO host bus (command 0) with the CPU halted | part of the MRA ROM image, written over the same host bus by an ioctl loader |
| $800000-$9FFFFF, $F00000-$F7FFFF | Zorro II RAM / unused | ROM board, BIOS, NVRAM and the $9FFFFE register, decoded beside Gary |
| CIA-A port B | parallel port | coin counters, start, service, DIP |
| inputs | USB joysticks / mouse / keyboard via the HPS | MiSTer joysticks 1 and 2, coin, start and service buttons |
| NVRAM | none | BRAM, saved to the SD card with the MiSTer NVRAM mechanism |

Removed from the build: AGA, 68020/030, RTG, IDE/Gayle, A2065, Toccata, CDTV, Akiko/CD32, MT-32, UART, floppy drives,
the shared folder.

ROM image (MRA `index="0"`; the layout is fixed by the loader and every MRA follows it):

| offset | size | contents |
|---|---|---|
| $000000 | 512 KB | Kickstart 1.3 (256 KB, twice) |
| $080000 | 512 KB | BIOS (`user2`, padded) |
| $100000 | 1.5 MB | ROM board (`user3`, padded with the set's fill byte) |

The scrambled low bytes are fixed by the loader as they arrive, using the permutation for the set, which the MRA gives in
a small configuration ROM (`index="1"`) along with the memory-map type (Arcadia or Aaargh).
