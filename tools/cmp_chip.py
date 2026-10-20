#!/usr/bin/env python3
"""Compare two chip RAM dumps (sim/tb_arcadia.cpp -dumpchip, tools/lua/arcadia_dump.lua chip_<f>.bin): the differing address
ranges, merged across gaps of up to 16 bytes, with the first words of each side.

    python3 tools/cmp_chip.py <a.bin> <b.bin> [max ranges]
"""
import sys


def main():
    a = open(sys.argv[1], 'rb').read()
    b = open(sys.argv[2], 'rb').read()
    mx = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    n = min(len(a), len(b))
    ranges = []
    i = 0
    while i < n:
        if a[i] != b[i]:
            s = i
            e = i
            while i < n and (a[i] != b[i] or i - e <= 16):
                if a[i] != b[i]:
                    e = i
                i += 1
            ranges.append((s, e + 1))
        else:
            i += 1
    total = sum(1 for k in range(n) if a[k] != b[k])
    print('%d differing bytes in %d ranges' % (total, len(ranges)))
    for s, e in ranges[:mx]:
        print('%06x-%06x (%5d)  a: %s  b: %s' % (s, e - 1, e - s, a[s:min(e, s + 12)].hex(' '), b[s:min(e, s + 12)].hex(' ')))


if __name__ == '__main__':
    main()
