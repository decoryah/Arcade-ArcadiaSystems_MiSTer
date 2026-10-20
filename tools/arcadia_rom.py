#!/usr/bin/env python3
"""Build the core's ROM image for one set from MAME's zips, exactly as the set's MRA assembles it.

    python3 tools/arcadia_rom.py <set> <romdir> <out.rom>

<romdir> holds ar_bios.zip and the game's zip (merged sets with the clone's files in a subfolder, or split sets); files are found
by CRC. The layout (rtl/arcadia_loader.v):

    $000000  16 bytes  header: the game's low-byte permutation (8 bytes, MAME's generic_decode order bit 7 .. bit 0),
                       flags (bit 0: Aaargh's map), 7 zero bytes
    $000010  512 KB    Kickstart 1.3 (256 KB twice)
    $080010  512 KB    BIOS (OnePlay 3.00: the -hi / -lo pair interleaved, then zero; Aaargh: zero)
    $100010  1.5 MB    ROM board (the -hi / -lo pairs interleaved, the rest the set's fill byte)

The ROM data stay as dumped: the loader unscrambles them.
"""
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arcadia_sets as A  # noqa: E402

HEADER = 0x10
KICK = 0x80000
BIOS = 0x80000
BOARD = 0x180000
SIZE = HEADER + KICK + BIOS + BOARD


def find_set(name):
    for s in A.SETS:
        if s['name'] == name:
            return s
    raise SystemExit('unknown set %s' % name)


def index_zips(romdir, names):
    by_crc = {}
    for z in names:
        path = os.path.join(romdir, z + '.zip')
        if not os.path.exists(path):
            continue
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                by_crc.setdefault('%08x' % info.CRC, (path, info.filename))
    return by_crc


def load(by_crc, name, crc):
    if crc not in by_crc:
        raise SystemExit('missing %s (crc %s)' % (name, crc))
    path, member = by_crc[crc]
    with zipfile.ZipFile(path) as zf:
        return zf.read(member)


def interleave(dst, base, data, half):
    o = base + (1 if half == 'lo' else 0)
    dst[o:o + 2 * len(data):2] = data


def build(s, romdir):
    zips = [s['name'], s['parent'], 'ar_bios']
    by_crc = index_zips(romdir, zips)
    img = bytearray(SIZE)
    img[0:8] = bytes(s['perm'])
    img[8] = 1 if s['argh'] else 0

    kick = load(by_crc, *A.KICKSTART)
    assert len(kick) == 0x40000
    img[HEADER:HEADER + 0x40000] = kick
    img[HEADER + 0x40000:HEADER + 0x80000] = kick

    if not s['argh']:
        for name, crc, off, half in A.BIOS:
            interleave(img, HEADER + KICK + off, load(by_crc, name, crc), half)

    board = HEADER + KICK + BIOS
    img[board:board + BOARD] = bytes([s['fill']]) * BOARD
    for name, crc, off, half, length, bad in s['files']:
        data = load(by_crc, name, crc)
        assert len(data) == length, name
        interleave(img, board + off, data, half)
    return img


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    s = find_set(sys.argv[1])
    img = build(s, sys.argv[2])
    with open(sys.argv[3], 'wb') as f:
        f.write(img)


if __name__ == '__main__':
    main()
