#!/bin/sh
# End-to-end bench of the MiSTer top level (ArcadiaSystems.sv): hps_io, the PLL and the SDRAM controller stubbed (sim/emu), the
# rest real: the machine, the 68000, the loader, fast loading, the video path with CRT Adjust, the framework's video_mixer
# (scandoubler, HQ2x, scanlines) and video_freak. Runs in WSL with Verilator 5.
#   sim/emu/run_emu.sh <image.rom> [frames after the load, default 30] [out prefix]
# FAST=1 loads through the DDR3, PRELOAD=1 skips the load; SNAPEVERY=n (default 10); the OSD settings: tb_emu.cpp. REBUILD=1.
set -e
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
cd "$(dirname "$0")"
IMG="$(realpath "$1")"; FR="${2:-30}"; PRE="${3:-out/emu}"
[ -f "$IMG" ] || { echo "usage: $0 <image.rom> [frames] [prefix]" >&2; exit 2; }
S=../../sys
M=../../modules/minimig
OBJ=${OBJ:-obj_emu}
mkdir -p $OBJ "$(dirname "$PRE")"
# The framework's video_mixer.sv declares R_in/G_in/B_in inside an unnamed generate block and uses them outside it; Quartus accepts
# that, Verilator does not: the bench builds a copy with the wires declared at module level (as the owner's Rabbit core's bench does)
python3 - $S/video_mixer.sv $OBJ/video_mixer_sim.sv <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'generate\s+if\(GAMMA && HALF_DEPTH\) begin.*?end else begin(.*?)end\s+endgenerate', s, re.S)
assert m, 'video_mixer.sv: the R_in generate block was not found'
open(sys.argv[2], 'w').write(s[:m.start()] + m.group(1).strip() + chr(10) + s[m.end():])
PY
if [ ! -x $OBJ/Vtb_emu_top ] || [ -n "$REBUILD" ]; then
echo '`define BUILD_DATE "000000"' > $OBJ/build_id.v
verilator --cc --exe --build -j ${JOBS:-16} -O3 -CFLAGS "-O2 -march=native" -Wno-fatal \
    -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-IMPLICIT -Wno-TIMESCALEMOD \
    -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
    -Wno-BLKSEQ -Wno-IMPLICITSTATIC -Wno-INITIALDLY -Wno-STMTDLY -Wno-COMBDLY -Wno-BLKANDNBLK -Wno-PINMISSING -Wno-CASEX \
    -Wno-ASCRANGE -Wno-PROCASSWIRE --no-timing --no-assert --public-flat-rw --savable --structs-packed \
    -I$OBJ -I../.. --top-module tb_emu_top --prefix Vtb_emu_top -Mdir $OBJ \
    ../../ArcadiaSystems.sv ../../rtl/arcadia_amiga.v ../../rtl/arcadia_board.v ../../rtl/arcadia_loader.v \
    ../../rtl/arcadia_fastload.v ../../rtl/arcadia_video.sv ../../modules/crt-adjust/crt_adjust.sv ../denise_colortable_ram_sim.v \
    $M/gary.v $M/userio.v $M/amiga_clk.v $M/minimig_syscontrol.v $M/minimig_sram_bridge.v $M/minimig_m68k_bridge.v \
    $M/minimig_bankmapper.v $M/agnus*.v $M/paula*.v $M/MiSTerFloppy*.v \
    $(ls $M/denise*.v | grep -v ram_mf) $M/ciaa.v $M/ciab.v $M/cia_int.v $M/cia_timera.v $M/cia_timerb.v $M/cia_timerd.v \
    $M/fx68k/fx68k.sv $M/fx68k/fx68kAlu.sv $M/fx68k/uaddrPla.sv \
    $OBJ/video_mixer_sim.sv $S/scandoubler.v $S/scanlines.v $S/gamma_corr.sv $S/hq2x.sv $S/video_freezer.sv $S/video_freak.sv $S/math.sv \
    $S/iir_filter.v hps_io_stub.sv stubs.sv ddr_model.sv tb_emu_top.sv tb_emu.cpp \
    > $OBJ.log 2>&1 || { grep -E "%Error|error:" $OBJ.log | grep -v "Command Failed" | head -20; exit 1; }
fi
# fx68k reads its microcode from the working directory
ln -sf $M/fx68k/microrom.mem microrom.mem
ln -sf $M/fx68k/nanorom.mem nanorom.mem
stdbuf -oL ./$OBJ/Vtb_emu_top "$IMG" "$FR" "$PRE"
