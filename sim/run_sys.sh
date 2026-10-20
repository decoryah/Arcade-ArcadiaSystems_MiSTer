#!/bin/sh
# The whole machine (sim/tb_top.sv) under Verilator, fed the MRA's ROM image through the loader.
#   sim/run_sys.sh <image.rom> <frames> <out prefix> [tb_arcadia options: -snap N,.. -snapevery K -sched FILE -bus A,B -dsw]
# (tools/arcadia_rom.py <set> <romdir> <image.rom> makes the image.) REBUILD=1 rebuilds the model; THREADS=n.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
[ -f "$1" ] && [ -n "$2" ] && [ -n "$3" ] || { echo "usage: $0 <image.rom> <frames> <prefix> [options]" >&2; exit 2; }
M=../modules/minimig
OBJ=${OBJ:-obj_sys}
if [ ! -x $OBJ/Vtb_top ] || [ -n "$REBUILD" ]; then
verilator --cc --exe --build -j ${JOBS:-16} -O3 ${THREADS:+--threads $THREADS} -CFLAGS "-O2 -march=native" -Wno-fatal \
    -Wno-WIDTH -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-IMPLICIT -Wno-TIMESCALEMOD \
    -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNSIGNED -Wno-CMPCONST -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
    -Wno-BLKSEQ -Wno-IMPLICITSTATIC -Wno-INITIALDLY -Wno-STMTDLY -Wno-COMBDLY -Wno-BLKANDNBLK -Wno-PINMISSING -Wno-CASEX \
    -Wno-ASCRANGE --no-timing --no-assert $VFLAGS --top-module tb_top --prefix Vtb_top -Mdir $OBJ \
    ../rtl/arcadia_amiga.v ../rtl/arcadia_board.v ../rtl/arcadia_loader.v denise_colortable_ram_sim.v \
    $M/gary.v $M/userio.v $M/amiga_clk.v $M/minimig_syscontrol.v $M/minimig_sram_bridge.v $M/minimig_m68k_bridge.v \
    $M/minimig_bankmapper.v $M/agnus*.v $M/paula*.v $M/MiSTerFloppy*.v \
    $(ls $M/denise*.v | grep -v ram_mf) $M/ciaa.v $M/ciab.v $M/cia_int.v $M/cia_timera.v $M/cia_timerb.v $M/cia_timerd.v \
    $M/fx68k/fx68k.sv $M/fx68k/fx68kAlu.sv $M/fx68k/uaddrPla.sv \
    tb_top.sv tb_arcadia.cpp > $OBJ.log 2>&1 || { tail -30 $OBJ.log; exit 1; }
fi
# fx68k reads its microcode from the working directory
ln -sf $M/fx68k/microrom.mem microrom.mem
ln -sf $M/fx68k/nanorom.mem nanorom.mem
IMG="$(realpath "$1")"; FR="$2"; PRE="$3"; shift 3
mkdir -p "$(dirname "$PRE")"
./$OBJ/Vtb_top "$IMG" "$FR" "$PRE" "$@"
