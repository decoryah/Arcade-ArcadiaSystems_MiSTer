# Vendored modules

Third-party HDL copied into the tree (no submodules, so the build is self-contained and reproducible). Each keeps its own
licence alongside.

| module | upstream | licence |
|---|---|---|
| minimig | https://github.com/MiSTer-devel/Minimig-AGA_MiSTer @ ec1353dc1b36e1c1a91fe14786ec7e09ec2a2cf1 (`rtl/` plus `hps_ext.v`; the upstream test benches under `rtl/sim`, `rtl/A2065/sim` and `rtl/fpga-toccata/sim` are left out) | GPL-3.0 or later |
| sys (top level) | the MiSTer framework as shipped in the same Minimig-AGA_MiSTer commit | GPL-3.0 or later |
| crt-adjust | https://github.com/rmonic79/MiSTer-CRT-Adjust @ c682de9f4acc61d8f4c7779efb48149d3baa3a8e (upstream's `rtl/crt_adjust.sv`), by rmonic79 (Umberto Parisi) with Andrea Bogazzi (asturur); copied from the owner's Rabbit core, which has one local fix (below) | GPL-3.0 or later |

To update one: re-copy from upstream at the new commit and record it here.

## Local changes

The first commit holds the upstream files unchanged, so `git log -p -- modules/minimig` shows every change made for the
Arcadia hardware. Each one is listed here as it is made.

* `gary.v`: the Arcadia memory map (MAME's `arcadia_map` / `argh_map`). It takes the ROM board switch and the Aaargh flag
  and gives three selects: the ROM board / BIOS in the SDRAM, the NVRAM, and the `$9FFFFE` switch. It moves the ROM board
  to `$200000` and the BIOS to `$700000` of the SRAM bridge's 8 MB, and maps `$E00000` to the Kickstart mirror. Reads of
  unmapped space return `$FFFF`, as in MAME (`unmap_value_high`). The ROM board and BIOS take host writes only with the
  CPU halted.
* `minimig_bankmapper.v`: an `arc` input, ORed into bank 4 (addressed like slow RAM).
* `ciaa.v`: port B gets a data register. It reads and drives as MAME's mos6526 does, and a new `portb_drive` output feeds
  the coin counters. Upstream has no port B register: reads return the pins and writes are dropped.
* `agnus.v`, `agnus_beamcounter.v`: an `ecs_id` input. VPOSR reports the ECS 8372 Agnus ID (`$30` with NTSC) while the
  ECS features stay off, as MAME's Arcadia (`AGNUS_HR_NTSC` with the OCS register map).

* `agnus_copper.v`: `copjmp1`, `copjmp2`, `strobe1`, `strobe2` and `strobe` change from `=` (blocking) to `<=`. They are
  assigned in clocked blocks and read by the others. Synthesis makes them flip-flops either way, but in simulation the
  readers can see the new value in the same edge, and the copper then never reloads its pointer at the start of a frame.
  Verilator showed this: the copper ran from a stale address, read a MOVE to register 0 and stopped. The synthesized
  logic does not change.

The PLL (`pll.v`, `pll.qip`, `pll/`) is copied to `rtl/`, where the MiSTer framework (`sys/pll_q17.qip`) expects it. It
gets a third output, `outclk_2`: the video clock, VCO / 8 = 56.750320 MHz (2x the machine clock, 57.27 MHz after the
NTSC reconfiguration). Minimig drives the video at 114 MHz for the ECS / AGA 28 MHz pixels. At that rate the framework's
S-video / composite encoder (`sys/yc_out.sv`) missed timing, and OCS needs no more than 57 MHz.

Everything else in `modules/minimig` is as upstream. The files the core does not build (68020/030, RTG, IDE, CD32,
CDTV, A2065, Toccata, MT-32, the HPS bridges) are kept as vendored. `minimig.v` and `Minimig.sv` are replaced by
`rtl/arcadia_amiga.v` and `ArcadiaSystems.sv`, which are derived from them.

### `crt-adjust/crt_adjust.sv`

Two local changes; nothing else differs from upstream.

* `hoff_s` (from the owner's Rabbit and Mystic Warriors cores): the conditional mixes `$signed(hoffset)` with an unsigned
  replication, so by the Verilog rules (and in Verilator) the result is unsigned and a negative H-Position is zero-extended
  (-1 becomes 511), which moves the picture window out of the line and blanks the picture. The line sign-extends `hoffset`
  explicitly, which is what the module is meant to do and gives the same result in every tool.
* `AW`, the line buffer's address width, is a parameter instead of a local constant (default 10, upstream's). An Amiga line
  is 908 or 912 dots at 14 MHz, the rate that keeps OCS hires pixels, and needs 1024 a bank: this core builds it with
  `AW = 11`.
