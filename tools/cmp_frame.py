#!/usr/bin/env python3
"""Compare a simulation frame (sim/tb_arcadia.cpp's raw beam PPM) with MAME's snapshot of the same frame.

    python3 tools/cmp_frame.py <sim.ppm> <mame.png> [out prefix] [--dx N --dy N]

The simulation's frame is the beam from hsync to hsync (14 MHz samples) and from vsync to vsync; MAME's snapshot is its visible
area (amiga_v.cpp ntsc_video: hires pixels 184-907 of the 908, lines doubled to 483 rows). The offset between the two is found from
the rows' and columns' brightness profiles (or given), MAME's rows are halved, and the pixels compared. Writes <prefix>_sim.png
(the simulation cut to MAME's area, lines doubled) and <prefix>_diff.png (differences in red) when a prefix is given.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio  # noqa: E402


def read_ppm(path):
    d = open(path, 'rb').read()
    parts, i = [], 0
    while len(parts) < 4:
        while d[i:i + 1].isspace():
            i += 1
        j = i
        while not d[j:j + 1].isspace():
            j += 1
        parts.append(d[i:j]); i = j
    i += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, bytearray(d[i:i + w * h * 3])


def profiles(w, h, px):
    rows = [0] * h
    cols = [0] * w
    for y in range(h):
        o = y * w * 3
        for x in range(w):
            v = px[o + x * 3] + px[o + x * 3 + 1] + px[o + x * 3 + 2]
            rows[y] += v
            cols[x] += v
    return rows, cols


def best_shift(a, b, lo, hi):
    """shift s in [lo, hi] minimising sum |a[i+s] - b[i]| (a the longer)"""
    best, bs = None, lo
    for s in range(lo, hi + 1):
        e = 0
        for i in range(len(b)):
            j = i + s
            e += abs((a[j] if 0 <= j < len(a) else 0) - b[i])
        if best is None or e < best:
            best, bs = e, s
    return bs


def main():
    args = sys.argv[1:]
    dx = dy = None
    if '--dx' in args:
        k = args.index('--dx'); dx = int(args[k + 1]); del args[k:k + 2]
    if '--dy' in args:
        k = args.index('--dy'); dy = int(args[k + 1]); del args[k:k + 2]
    sw, sh, sp = read_ppm(args[0])
    mw, mh2, mp2 = pngio.read(args[1])
    prefix = args[2] if len(args) > 2 else None
    mh = mh2 // 2
    mp = bytearray(mw * mh * 3)
    for y in range(mh):
        mp[y * mw * 3:(y + 1) * mw * 3] = mp2[(2 * y) * mw * 3:(2 * y + 1) * mw * 3]

    if dx is None or dy is None:
        srows, scols = profiles(sw, sh, sp)
        mrows, mcols = profiles(mw, mh, mp)
        if dy is None:
            dy = best_shift(srows, mrows, -10, 60)
        if dx is None:
            dx = best_shift(scols, mcols, 0, max(0, sw - mw) + 200)

    diff = 0
    out = bytearray(mw * mh * 3)
    dimg = bytearray(mw * mh * 3)
    for y in range(mh):
        for x in range(mw):
            sx, sy = x + dx, y + dy
            if 0 <= sx < sw and 0 <= sy < sh:
                s = sp[(sy * sw + sx) * 3:(sy * sw + sx) * 3 + 3]
            else:
                s = b'\0\0\0'
            m = mp[(y * mw + x) * 3:(y * mw + x) * 3 + 3]
            o = (y * mw + x) * 3
            out[o:o + 3] = s
            if bytes(s) != bytes(m):
                diff += 1
                dimg[o:o + 3] = b'\xff\x00\x00'
            else:
                g = (m[0] + m[1] + m[2]) // 6
                dimg[o:o + 3] = bytes([g, g, g])
    print('offset dx=%d dy=%d  pixels %d  differing %d (%.2f%%)' % (dx, dy, mw * mh, diff, 100.0 * diff / (mw * mh)))
    if prefix:
        dbl = bytearray()
        for y in range(mh):
            dbl += out[y * mw * 3:(y + 1) * mw * 3] * 2
        pngio.write(prefix + '_sim.png', mw, mh * 2, dbl)
        dd = bytearray()
        for y in range(mh):
            dd += dimg[y * mw * 3:(y + 1) * mw * 3] * 2
        pngio.write(prefix + '_diff.png', mw, mh * 2, dd)


if __name__ == '__main__':
    main()
