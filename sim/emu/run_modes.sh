#!/bin/bash
# The video modes on the MiSTer top level (sim/emu/run_emu.sh, built once), several runs at a time: Scandoubler Fx (HQ2x, the CRT
# filters), MiSTer.ini's forced_scandoubler, CRT Adjust, Scale and the aspect ratio. Every run starts from a saved model (the OnePlay
# screen: run_emu.sh with SAVEAT / SAVE), gets its settings at once, and checks its own raster (sim/emu/tb_emu.cpp: a vertical sync
# every frame, the frame period, the rows and lines, where the rows sit, the size asked of the scaler); sim/emu/cmp_modes.py then
# compares its pictures with the plain run's of the same frame, which shows a frozen or shifted picture.
#   sim/emu/run_modes.sh <image.rom> <saved model> <out dir> [frames, default 12]
# JOBS runs at a time (default 8).
cd "$(dirname "$0")"
IMG="$(realpath "$1")"; SAV="$(realpath "$2")"; OUT="$3"; FR="${4:-12}"
[ -f "$IMG" ] && [ -f "$SAV" ] && [ -n "$OUT" ] || { echo "usage: $0 <image.rom> <saved model> <out dir> [frames]" >&2; exit 2; }
mkdir -p "$OUT"; OUT="$(realpath "$OUT")"
[ -x obj_emu/Vtb_emu_top ] || { echo "build the bench first: sim/emu/run_emu.sh (REBUILD=1)" >&2; exit 2; }
ln -sf ../../modules/minimig/fx68k/microrom.mem microrom.mem
ln -sf ../../modules/minimig/fx68k/nanorom.mem nanorom.mem
# name and settings (tb_emu.cpp); the expected raster: 263 lines of 241 rows, twice that through the scandoubler
MODES=(
  "base:EXPECT_LINES=263 EXPECT_ROWS=241"
  "hq2x:FX=1 EXPECT_LINES=526 EXPECT_ROWS=482"
  "crt25:FX=2 EXPECT_LINES=526 EXPECT_ROWS=482"
  "crt50:FX=3 EXPECT_LINES=526 EXPECT_ROWS=482"
  "crt75:FX=4 EXPECT_LINES=526 EXPECT_ROWS=482"
  "fsd:FSD=1 EXPECT_LINES=526 EXPECT_ROWS=482"
  "fsd_crt50:FSD=1 FX=3 EXPECT_LINES=526 EXPECT_ROWS=482"
  "fsd_hq2x:FSD=1 FX=1 EXPECT_LINES=526 EXPECT_ROWS=482"
  "crt_on:CRT=1 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_size_max:CRT=1 HSIZE=6 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_size_min:CRT=1 HSIZE=-16 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_pos_max:CRT=1 HPOS=32 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_pos_min:CRT=1 HPOS=-48 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_vs_max:CRT=1 VSHIFT=15 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_vs_min:CRT=1 VSHIFT=-16 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_all:CRT=1 HSIZE=4 HPOS=-10 VSHIFT=3 EXPECT_LINES=263 EXPECT_ROWS=241"
  "crt_under_sd:CRT=1 HSIZE=4 HPOS=-10 VSHIFT=3 FX=2 EXPECT_LINES=526 EXPECT_ROWS=482"
  "crt_under_fsd:CRT=1 HSIZE=4 FSD=1 EXPECT_LINES=526 EXPECT_ROWS=482"
  "scale_v:SCALE=1"
  "scale_hv:SCALE=2"
  "scale_nhv:SCALE=3"
  "scale_hvp:SCALE=4"
  "scale_hv_fs:SCALE=2 AR=1"
  "scale_hv_1280:SCALE=2 HW=1280 HH=720"
  "scale_hvp_hq2x:SCALE=4 FX=1"
  "scale_v_crt:SCALE=1 CRT=1"
)
run_one() {
  local name="${1%%:*}" set="${1#*:}"
  env RESTORE="$SAV" SNAPEVERY=4 $set ./obj_emu/Vtb_emu_top "$IMG" "$FR" "$OUT/$name" > "$OUT/$name.log" 2>&1
  echo "$name: $(grep -E "^(PASS|FAIL)" "$OUT/$name.log" | tail -1)"
}
export -f run_one; export IMG SAV FR OUT
printf '%s\n' "${MODES[@]}" | xargs -P "${JOBS:-8}" -I{} bash -c 'run_one "$@"' _ {}
echo "--- pictures against the plain run's"
python3 cmp_modes.py "$OUT"
