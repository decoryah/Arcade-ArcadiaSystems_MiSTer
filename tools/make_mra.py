#!/usr/bin/env python3
"""Write the MRA files: one per MAME 0.289 set (tools/arcadia_sets.py), parents in mra/, clones in mra/_alternatives/_<title>/.

    python3 tools/make_mra.py [romdir]

With a romdir (MAME's zips), every MRA is also assembled with tools/mra_build.py and checked byte for byte against
tools/arcadia_rom.py's image, which is what the simulation runs, and the MRA gets that image's md5.
The image layout is rtl/arcadia_loader.v's (see tools/arcadia_rom.py).
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import arcadia_sets as A  # noqa: E402
import arcadia_rom  # noqa: E402

ROOT = os.path.dirname(HERE)
MRA_DIR = os.path.join(ROOT, 'mra')

# What the two buttons do in each game (a clone plays as its parent), as the games' own control screens and play in MAME 0.289
# show them; "-" for a button the game does not use. The core's inputs are Button 1, Button 2, Start, Coin (ArcadiaSystems.sv's J1
# line): Main_MiSTer shows these names in place of the core's.
BUTTON_NAMES = {
    'ar_airh':  ('Speed Up', 'Speed Up'),           # "Fire increases player speed"; the game takes either button
    'ar_argh':  ('Fire', 'Punch'),                  # the how-to-play screen: fire button flames, punch button punches
    'ar_blast': ('Fire', 'Accelerate'),             # "FIRE 1 FIRE ENERGY BALL", "FIRE 2 ACCELERATE"
    'ar_bowl':  ('Throw', 'Throw'),                 # the game takes either button
    'ar_dart':  ('Throw', '-'),                     # "press the RED fire button to throw"; button 2 is never read
    'ar_dlta':  ('Fire', 'Special Weapon'),         # button 2 fires the special weapon (rockets), with its own counter
    'ar_fast':  ('Shoot / Jump', 'Pass / Switch'),  # the control screen: offence shoot / pass, defence jump / switch player
    'ar_ldrb':  ('Select Club', 'Top View'),        # "SELECT A CLUB ... FIRE BUTTON 1", "TOP VIEW ... FIRE BUTTON 2"
    'ar_ninj':  ('Punch / Kick', 'Sword'),          # "joystick + FIRE 1" punches and kicks, "FIRE 2" the sword
    'ar_pm':    ('Select', 'Cancel'),
    'ar_rdwr':  ('Fire', '-'),                      # button 2 changes nothing in play
    'ar_sdwr':  ('Fire', '-'),                      # "Use fire button 1 to shoot ground and air targets"
    'ar_socc':  ('Kick', 'Switch Player'),          # the control screen: kick / slide / header, change player
    'ar_spot':  ('Select', '-'),
    'ar_sprg':  ('Fire', 'Net'),                    # "FIRE BUTTON 1 to shoot slavers ... FIRE BUTTON 2 to net critters"
    'ar_xeon':  ('Fire', 'Transform'),              # jet <-> tank
}
FAST_LOAD_ADDRESS = '0x32000000'   # rtl/arcadia_fastload.v: where Main_MiSTer puts the image with address= (the attribute other cores use)


def buttons(s):
    b1, b2 = BUTTON_NAMES[s['name'] if s['parent'] == 'ar_bios' else s['parent']]
    return '<buttons names="%s,%s,Start,Coin" default="A,B,Start,Select"/>' % (b1, b2)


def short_title(title):
    """'Space Ranger (Arcadia, V 2.0)' -> 'Space Ranger'"""
    return re.sub(r'\s*\(.*\)$', '', title)


def file_name(title):
    return title.replace('/', '-').replace(':', ' -') + '.mra'


def pairs(files):
    by_off = {}
    for name, crc, off, half, length, bad in files:
        by_off.setdefault(off, {})[half] = (name, crc, bad)
    return sorted(by_off.items())


def mra_text(s, md5='None'):
    zips = [s['name'] + '.zip']
    if s['parent'] != 'ar_bios':
        zips.append(s['parent'] + '.zip')
    zips.append('ar_bios.zip')
    L = []
    L.append('<misterromdescription>')
    L.append('    <name>%s</name>' % s['title'])
    L.append('    <setname>%s</setname>' % s['name'])
    L.append('    <mameversion>0289</mameversion>')
    L.append('    <year>%d</year>' % s['year'])
    L.append('    <manufacturer>Arcadia Systems</manufacturer>')
    L.append('    <players>2</players>')
    L.append('    <joystick>%d</joystick>' % (4 if s['four_way'] else 8))
    L.append('    <rotation>horizontal</rotation>')
    L.append('    <rbf>arcadiasystems</rbf>')
    L.append('    <platform>Arcadia Systems</platform>')
    L.append('    <!-- The image (rtl/arcadia_loader.v): a 16-byte header (the ROM board\'s low-byte permutation, MAME\'s generic_decode')
    L.append('         order bit 7..0; flags, bit 0 Aaargh\'s map), Kickstart 1.3 (512 KB), the BIOS (512 KB, OnePlay 3.00 as MAME\'s')
    L.append('         default), the ROM board (1.5 MB). The ROMs stay as dumped: the core unscrambles them.')
    L.append('         Expects the MAME 0.289 merged romset or the split sets. address=: fast loading, the image through the DDR3 (a')
    L.append('         Main_MiSTer without it streams the image). Written by tools/make_mra.py. -->')
    L.append('    ' + buttons(s))
    L.append('    <rom index="0" zip="%s" md5="%s" address="%s">' % ('|'.join(zips), md5, FAST_LOAD_ADDRESS))
    hdr = list(s['perm']) + [1 if s['argh'] else 0] + [0] * 7
    L.append('        <!-- header -->')
    L.append('        <part>%s</part>' % ' '.join('%02X' % b for b in hdr))
    name, crc = A.KICKSTART
    L.append('        <!-- kickstart: Kickstart 1.3, twice -->')
    L.append('        <part name="%s" crc="%s"/>' % (name, crc))
    L.append('        <part name="%s" crc="%s"/>' % (name, crc))
    if s['argh']:
        L.append('        <!-- user2: none (Aaargh has no BIOS) -->')
        L.append('        <part repeat="0x80000">00</part>')
    else:
        L.append('        <!-- user2: the BIOS, OnePlay 3.00 -->')
        L.append('        <interleave output="16">')
        for name, crc, off, half in A.BIOS:
            L.append('            <part name="%s" crc="%s" map="%s"/>' % (name, crc, '01' if half == 'hi' else '10'))
        L.append('        </interleave>')
        L.append('        <part repeat="0x60000">00</part>')
    L.append('        <!-- user3: the ROM board -->')
    used = 0
    for off, p in pairs(s['files']):
        assert off == used, (s['name'], hex(off))
        L.append('        <interleave output="16">')
        for half, mp in (('hi', '01'), ('lo', '10')):
            name, crc, bad = p[half]
            L.append('            <part name="%s" crc="%s" map="%s"/>%s' % (name, crc, mp, '  <!-- MAME: BAD_DUMP -->' if bad else ''))
        L.append('        </interleave>')
        used = off + 0x20000
    if used < 0x180000:
        L.append('        <part repeat="0x%X">%02X</part>' % (0x180000 - used, s['fill']))
    L.append('    </rom>')
    L.append('    <nvram index="4" size="%d"/>' % (4096 if s['argh'] else 16384))
    L.append('</misterromdescription>')
    return '\n'.join(L) + '\n'


def main():
    romdir = sys.argv[1] if len(sys.argv) > 1 else None
    if romdir:
        import mra_build
    titles = {s['name']: short_title(s['title']) for s in A.SETS}
    n = 0
    for s in A.SETS:
        if s['not_working']:
            continue
        if s['parent'] == 'ar_bios':
            d = MRA_DIR
        else:
            d = os.path.join(MRA_DIR, '_alternatives', '_' + titles[s['parent']])
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, file_name(s['title']))

        def write(md5):
            with open(path, 'w', encoding='utf-8', newline='\n') as f:
                f.write(mra_text(s, md5))

        write('None')
        if romdir:
            # Main_MiSTer's md5 is over each part's bytes in the order of the MRA (support/arcade/mra_loader.cpp, rom_data),
            # not over the assembled image: mra_build.py computes it; the assembled image must equal arcadia_rom.py's
            img = arcadia_rom.build(s, romdir)
            zips = '|'.join(os.path.join(romdir, z) for z in
                            [s['name'] + '.zip', s['parent'] + '.zip', 'ar_bios.zip'] if os.path.exists(os.path.join(romdir, z)))
            built, md5 = mra_build.build(path, zips)
            assert bytes(built) == bytes(img), s['name']
            write(md5)
            assert mra_build.build(path, zips)[1] == md5
        n += 1
        print('%-9s %s' % (s['name'], os.path.relpath(path, ROOT)))
    print('%d MRAs%s' % (n, ', each checked against tools/arcadia_rom.py' if romdir else ''))


if __name__ == '__main__':
    main()
