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
diagnostic-ROM magic and for resident tags ($4AFC). OnePlay and TenPlay both start with a resident tag (OnePlay's
scrambled first word unscrambles to $4AFC); see section 5 for what OnePlay does with it.

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
| Kickstart | uploaded by the HPS over the UIO host bus (command 0) with the CPU halted | part of the MRA ROM image, written straight into the SDRAM controller by an ioctl loader (or from the DDR3: fast loading) |
| $800000-$9FFFFF, $F00000-$F7FFFF | Zorro II RAM / unused | ROM board, BIOS, NVRAM and the $9FFFFE register, decoded beside Gary |
| CIA-A port B | parallel port | coin counters, start, service, DIP |
| inputs | USB joysticks / mouse / keyboard via the HPS | MiSTer joysticks 1 and 2 with coin and start; service on the keyboard (F2) |
| NVRAM | none | BRAM, saved to the SD card with the MiSTer NVRAM mechanism |

Removed from the build: AGA, 68020/030, RTG, IDE/Gayle, A2065, Toccata, CDTV, Akiko/CD32, MT-32, UART, floppy drives,
the shared folder.

Clocks: Minimig's PLL is built for PAL and reconfigured to NTSC right after power-on, as Minimig does when the machine
reports NTSC. It drives three clocks:

| clock | frequency | used for |
|---|---|---|
| machine clock | 28.636 MHz (MAME's `CLK_28M_NTSC`) | the chipset and the 68000 (7.159 MHz, on phase enables) |
| 4x clock | 114.5 MHz | the SDRAM and the 68000's phase enables |
| video clock | 57.27 MHz | the MiSTer video path. Minimig uses 114 MHz here for ECS / AGA's 28 MHz pixels; OCS's are 14 MHz at most |

The timing constraints add the NTSC clock's 0.92 % to the setup checks (`ArcadiaSystems.sdc`).

ROM image (MRA `index="0"`; the layout is fixed by `rtl/arcadia_loader.v` and every MRA follows it):

| offset | size | contents | written to |
|---|---|---|---|
| $000000 | 16 bytes | header: the ROM board's low-byte permutation (MAME's `generic_decode` order, bit 7 .. bit 0), flags (bit 0 Aaargh's map), zeros | the loader |
| $000010 | 512 KB | Kickstart 1.3 (256 KB, twice) | $F80000 (SDRAM $780000) |
| $080010 | 512 KB | BIOS (`user2`, the rest zero; Aaargh: all zero) | $F00000 (SDRAM $700000) |
| $100010 | 1.5 MB | ROM board (`user3`, the rest the set's fill byte) | $800000 (SDRAM $200000) |

The loader fixes the scrambled low bytes as they pass (the ROM board's first 128 KB with the header's permutation, the
BIOS's first 128 KB with OnePlay's when the BIOS's first word is not `$4AFC`) and writes the image word by word straight
into the SDRAM controller's chip port, one word in a 7 MHz slot, in place of the machine's own access, at the addresses
the SRAM bridge gives those regions (the last column above). Minimig's way, Main_MiSTer writing a Kickstart over the
68000's bus, takes a bus cycle (0.8 us) a word: the 2.5 MB image took 1.1 s that way however fast it came. Now the
loader keeps up with whatever sends it the image: in the simulated top level a fast load has it in memory 0.39 s after
it starts. The loader holds the 68000 in reset from power-on and during every download (the NVRAM file comes after the
ROMs), and lets it go about 150 ms after the last one ends and its last word is written, with a machine reset.

Fast loading: the MRAs carry `address="0x32000000"` on the ROM image, the attribute other MiSTer arcade cores use. A
Main_MiSTer that knows it copies the assembled image into the DDR3 at that byte address in one go and sends a download
with no data whose start address is the image's length; `rtl/arcadia_fastload.v` then reads the image back in 256-byte
bursts and hands it to the loader byte by byte, as the ioctl port would, so the result is the same as a streamed load.
A Main_MiSTer that ignores the attribute streams the image (its download starts at address 0).

How the OnePlay BIOS takes over (seen in MAME and in the simulation): its resident tag at `$F00000` ("strap", priority
-59, init at `$9902BC`, so it runs from the `$980000` window) points ExecBase's CoolCapture at `$990342`. It puts
`reset; jmp` at address 0 and jumps there. The RESET instruction brings back the Kickstart overlay, so the prefetched
`jmp` takes its target from ROM: a warm reboot. On the second start Kickstart calls CoolCapture, and OnePlay runs.
