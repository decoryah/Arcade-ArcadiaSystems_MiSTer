#!/usr/bin/env python3
"""The pictures of sim/emu/run_modes.sh's runs against the plain run's ("base") of the same frame.

    python3 sim/emu/cmp_modes.py <out dir>

A picture is what the scaler gets (VGA_* on CE_PIXEL with VGA_DE), row by row. The plain run gives Minimig's 28 MHz dots (four to
a lores pixel); the scandoubler gives every row twice at the frame's own resolution (7 MHz for lores, twice as wide with HQ2x);
CRT Adjust gives 14 MHz dots. So each picture is compared at its own rate: its rows (the even ones, doubled) against every
k-th dot of the plain run's rows, at the phase that matches best. A frozen picture shows as a run of identical frames where the
plain run's change; a shifted or missing one as a low match. Runs that move or resize the picture (CRT Adjust's settings) are
listed with their match but not judged; the others must match fully, HQ2x but for its interpolated edges.
"""
import glob
import os
import re
import sys


def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    m = re.match(rb'P6\s+(\d+)\s+(\d+)\s+255\s', data)
    w, h = int(m.group(1)), int(m.group(2))
    px = data[m.end():]
    return w, h, [px[y * w * 3:(y + 1) * w * 3] for y in range(h)]


def match(base, pic):
    bw, bh, brows = base
    w, h, rows = pic
    step = 2 if h == 2 * bh else 1
    if w == 0 or h == 0:
        return 0.0
    k = max(1, round(bw / w))
    best = 0.0
    for off in range(step):
        sel = rows[off::step][:bh]
        for ph in range(k):
            same = total = 0
            for y, r in enumerate(sel):
                b = brows[y]
                for x in range(min(w, (bw - ph + k - 1) // k)):
                    total += 1
                    if r[3 * x:3 * x + 3] == b[3 * (x * k + ph):3 * (x * k + ph) + 3]:
                        same += 1
            if total:
                best = max(best, same / total)
    return best


def main():
    out = sys.argv[1]
    base = {os.path.basename(p)[len('base.'):]: read_ppm(p) for p in glob.glob(os.path.join(out, 'base.f*.ppm'))}
    frames = sorted(f for f in base if not f.startswith('f0000'))
    if len(frames) >= 2 and all(base[a][2] == base[frames[0]][2] for a in frames):
        print('note: the plain run\'s pictures do not change over these frames')
    judged_bad = 0
    for log in sorted(glob.glob(os.path.join(out, '*.log'))):
        name = os.path.basename(log)[:-4]
        if name == 'base':
            continue
        ms = []
        for f in frames:
            p = os.path.join(out, '%s.%s' % (name, f))
            if os.path.exists(p):
                ms.append(match(base[f], read_ppm(p)))
        if not ms:
            print('%-16s no pictures' % name)
            continue
        moved = re.match(r'crt_(size|pos|vs|all)', name) is not None
        need = 0.97 if 'hq2x' in name else 1.0
        ok = moved or min(ms) >= need
        judged_bad += 0 if ok else 1
        print('%-16s %s  same dots: %s' % (name, 'moved (not judged)' if moved else ('ok' if ok else 'DIFFERS'),
                                          ', '.join('%.4f' % m for m in ms)))
    print('pictures: %s' % ('all as the plain run' if not judged_bad else '%d runs differ' % judged_bad))
    return 1 if judged_bad else 0


if __name__ == '__main__':
    sys.exit(main())
