#!/bin/sh
# MAME 0.289 runs with tools/lua/arcadia_dump.lua (Git Bash on Windows): a fresh NVRAM every run (MAME's nvram is deleted first),
# so runs repeat.
#   tools/mame_dump.sh <set> <out dir> <frames "a,b,c"> [schedule file] [last frame] [snap every]
# MAME, its ROM path and a work directory are taken from MAME / ROMPATH / WORK (defaults: the owner's MAME; the ROMs and the
# work directory in the scratch folder work/ next to the repository).
HERE=$(cd "$(dirname "$0")" && pwd)
SCRATCH=$(cd "$HERE/../.." && pwd)/work
MAME=${MAME:-/c/repos/mame0289/mame.exe}
ROMPATH=${ROMPATH:-$(cygpath -m "$SCRATCH/roms" 2>/dev/null || echo "$SCRATCH/roms")}
WORK=${WORK:-$SCRATCH/mame_run}
SET="$1"; OUT="$2"; FR="$3"; SCHEDF="$4"; LASTF="$5"; EVERY="$6"
mkdir -p "$OUT" "$WORK"
[ -n "$SCHEDF" ] && SCHEDF="$(cygpath -m "$(realpath "$SCHEDF")" 2>/dev/null || echo "$SCHEDF")"
cd "$WORK" && rm -rf "nvram/$SET"
DUMPFRAMES="$FR" DUMPDIR="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")" SCHED="$SCHEDF" LASTFRAME="$LASTF" SNAPEVERY="$EVERY" \
    "$MAME" "$SET" -rompath "$ROMPATH" -video none -sound none -nothrottle -skip_gameinfo -window -cfg_directory cfg \
    -nvram_directory nvram -autoboot_script "$(cygpath -m "$HERE/lua/arcadia_dump.lua")" -seconds_to_run 100000 2>&1 | tail -2
