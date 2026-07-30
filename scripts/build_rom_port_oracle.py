#!/usr/bin/env python
"""Gospel-derived expected byte view for every gladiator_roms read port.

Ground truth (in reliability order, project source notes):
  * ROM bytes            -- roms/gladiatr.zip, CRC32-gated against ROM_START.
  * MAME source          -- gladiatr.cpp ROM_START(gladiatr) lines 1139..1192
                            and gladiatr_state::init_gladiatr lines 1360..1396.

The regions below are rebuilt from the zip exactly the way MAME's ROM loader
plus init_gladiatr build them.  The per-port views are then expressed in terms
of the MAME region byte the *consumer* is entitled to see:

  main   -> gladiator_main_bus.sv:136..145 program-bank map
  adpcm  -> gladiator_6809_bus.sv:41..50   adpcm-bank map
  others -> the region is copied straight through

Nothing here reads sim/out/gladiatr.rom and nothing imports build_rom.py or any
RTL index arithmetic; the oracle is written blind from the gospel so that a
cross-diff against gladiator_roms.sv is a real two-sided check.

Emits sim/out/rom-ports/<port>.hex, one hex byte per line, consumed by
sim/unit/tb_rom_download.sv via $readmemh into a bench-local array.
"""

import argparse
import os
import zipfile
import zlib

# gladiatr.cpp:1139-1192 -- name, CRC32 from ROM_LOAD.
ROM_CRC = {
    "qb0_5": 0x25B19EFB, "qb0_4": 0x347EC794, "qb0_1": 0x040C9839,
    "qc0_3": 0x8D182326, "qb0_17": 0xE78BE010, "qb0_20": 0x15916EDA,
    "qb0_19": 0x79CAA7ED, "qb0_18": 0xE9591260, "qc0_15": 0xA7EFA340,
    "qb0_12": 0x0585D9AC, "qb0_13": 0xA6BB797B, "qb0_14": 0x85B71211,
    "qc1_6": 0x651E6E44, "qc2_7": 0xC992C4F7, "qc0_8": 0x1C7FFDAD,
    "qc1_9": 0x01043E03, "qc1_10": 0x364CDB58, "qc2_11": 0xC9FECFFF,
    "q3.2b": 0x6A7C3C60, "q4.5s": 0xE325808E, "aq_002.9b": 0xB30D225F,
    "aq_003.xx": 0x1D02CD5F, "aq_006.3A": 0x3C5CA4C6, "aq_007.6c": 0xF19AF04D,
}


def load_zip(path):
    zf = zipfile.ZipFile(path)
    have = {n.lower(): n for n in zf.namelist()}
    out = {}
    for name, crc in ROM_CRC.items():
        real = have.get(name.lower())
        if real is None:
            raise SystemExit("missing ROM %s in %s" % (name, path))
        data = zf.read(real)
        got = zlib.crc32(data) & 0xFFFFFFFF
        if got != crc:
            raise SystemExit("CRC mismatch %s: got %08x want %08x"
                             % (name, got, crc))
        out[name.lower()] = data
    return out


def build_regions(rom):
    g = lambda n: rom[n.lower()]

    # ROM_REGION(0x1c000, "maincpu") -- gladiatr.cpp:1140-1146
    main = bytearray(0x1C000)
    main[0x00000:0x04000] = g("qb0_5")
    main[0x04000:0x06000] = g("qb0_4")
    d = g("qb0_1")                                   # ROM_CONTINUE 0x16000
    main[0x10000:0x12000] = d[:0x2000]
    main[0x16000:0x18000] = d[0x2000:]
    d = g("qc0_3")                                   # ROM_CONTINUE 0x18000
    main[0x12000:0x16000] = d[:0x4000]
    main[0x18000:0x1C000] = d[0x4000:]

    # ROM_REGION(0x10000, "sub") -- gladiatr.cpp:1148-1149
    sub = bytearray(0x10000)
    sub[0x0000:0x4000] = g("qb0_17")

    # ROM_REGION(0x28000, "audiocpu") -- gladiatr.cpp:1151-1157
    au = bytearray(0x28000)
    for name, lo, hi in (("qb0_20", 0x10000, 0x1C000),
                         ("qb0_19", 0x14000, 0x20000),
                         ("qb0_18", 0x18000, 0x24000)):
        d = g(name)
        au[lo:lo + 0x4000] = d[:0x4000]
        au[hi:hi + 0x4000] = d[0x4000:]

    # ROM_REGION(0x02000, "tx_tiles") -- gladiatr.cpp:1159-1160
    tx = bytearray(g("qc0_15"))

    # ROM_REGION(0x20000, "bg_tiles") -- gladiatr.cpp:1162-1166
    bg = bytearray(0x20000)
    bg[0x00000:0x08000] = g("qb0_12")
    bg[0x10000:0x18000] = g("qb0_13")
    bg[0x18000:0x20000] = g("qb0_14")

    # ROM_REGION(0x30000, "sprites") -- gladiatr.cpp:1168-1175
    sp = bytearray(0x30000)
    sp[0x00000:0x04000] = g("qc1_6")
    sp[0x04000:0x0C000] = g("qc2_7")
    sp[0x18000:0x1C000] = g("qc0_8")
    sp[0x1C000:0x20000] = g("qc1_9")
    sp[0x20000:0x28000] = g("qc1_10")
    sp[0x28000:0x30000] = g("qc2_11")

    # ROM_REGION(0x40, "proms") -- gladiatr.cpp:1177-1179
    pr = bytearray(0x40)
    pr[0x00:0x20] = g("q3.2b")
    pr[0x20:0x40] = g("q4.5s")

    # ROM_REGION 0x400/0x400/0x400/0x800 MCUs -- gladiatr.cpp:1181-1191.
    # These stay RAW: init_gladiatr's 0x22 byte-0 patch belongs to the MCU ROM
    # adapter (rtl/compat/gladiator_mcu_rom_adapter.sv:14), not to the ROM
    # store, so the cctl/ccpu read ports must return the undoctored dump.
    cctl = bytearray(g("aq_002.9b"))
    ccpu = bytearray(g("aq_003.xx"))
    ucpu = bytearray(g("aq_006.3A"))
    csnd = bytearray(g("aq_007.6c"))

    # init_gladiatr 3bpp unpack + sort -- gladiatr.cpp:1360-1392
    def unpack(rom_, jmax):
        for j in range(jmax, -1, -1):
            for i in range(0x2000):
                v = rom_[i + j * 0x2000]
                rom_[i + (2 * j + 1) * 0x2000] = v >> 4
                rom_[i + 2 * j * 0x2000] = v

    def swap(rom_, a, b, n):
        t = rom_[a:a + n]
        rom_[a:a + n] = rom_[b:b + n]
        rom_[b:b + n] = t

    unpack(bg, 3)
    swap(bg, 0x14000, 0x18000, 0x4000)

    unpack(sp, 5)
    swap(sp, 0x1A000, 0x1C000, 0x2000)
    swap(sp, 0x22000, 0x28000, 0x2000)
    swap(sp, 0x26000, 0x2C000, 0x2000)
    swap(sp, 0x24000, 0x28000, 0x4000)

    return dict(main=main, sub=sub, au=au, tx=tx, bg=bg, sp=sp, pr=pr,
                cctl=cctl, ccpu=ccpu, ucpu=ucpu, csnd=csnd)


def main_view(a):
    """gladiator_main_bus.sv:136-145 -- Z80 sees rom_address; that address
    indexes the maincpu region as 0x0000-0x5fff fixed, then two 0x2000 banks
    at 0x6000 and two 0x4000 banks at 0xa000 (MAME m_mainbank 0x6000 stride,
    gladiatr.cpp:1398)."""
    if a < 0x6000:
        return a
    if a < 0xA000:
        return 0x10000 + ((a - 0x6000) // 0x2000) * 0x6000 + \
               ((a - 0x6000) % 0x2000)
    return 0x12000 + ((a - 0xA000) // 0x4000) * 0x6000 + \
           ((a - 0xA000) % 0x4000)


def adpcm_view(a):
    """gladiator_6809_bus.sv:41-50 -- bit14 of the port address is the bank
    select, the 0x8000-strided chunk index is the offset inside the bank
    (MAME m_adpcmbank 0xc000 stride, gladiatr.cpp:1399)."""
    return 0x10000 + ((a >> 14) & 1) * 0xC000 + (a >> 15) * 0x4000 + \
           (a & 0x3FFF)


def build_ports(r):
    main, au = r["main"], r["au"]
    bg, sp = r["bg"], r["sp"]
    ports = {}
    ports["main"] = bytes(main[main_view(a)] for a in range(0x12000))
    ports["sound"] = bytes(r["sub"][0:0x4000])
    ports["adpcm"] = bytes(au[adpcm_view(a)] for a in range(0x18000))
    ports["text"] = bytes(r["tx"][0:0x2000])
    # gfxlayout half_bits split: plane 3 is the low half of the unpacked
    # region, planes 1+2 the high half (gladiatr.cpp GFXDECODE / init unpack).
    ports["bg_plane0"] = bytes(bg[0x00000:0x10000])
    ports["bg_plane12"] = bytes(bg[0x10000:0x20000])
    ports["sprite_plane0"] = bytes(sp[0x00000:0x18000])
    ports["sprite_plane12"] = bytes(sp[0x18000:0x30000])
    ports["prom_q3"] = bytes(r["pr"][0x00:0x20])
    ports["prom_q4"] = bytes(r["pr"][0x20:0x40])
    ports["cctl"] = bytes(r["cctl"])
    ports["ccpu"] = bytes(r["ccpu"])
    ports["ucpu"] = bytes(r["ucpu"])
    ports["csnd"] = bytes(r["csnd"])
    return ports


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", default="roms/gladiatr.zip")
    ap.add_argument("--out", default="sim/out")
    args = ap.parse_args()

    regions = build_regions(load_zip(args.zip))
    ports = build_ports(regions)

    dest = os.path.join(args.out, "rom-ports")
    os.makedirs(dest, exist_ok=True)
    total = 0
    for name, data in sorted(ports.items()):
        with open(os.path.join(dest, name + ".hex"), "w") as fh:
            fh.write("".join("%02x\n" % b for b in data))
        total += len(data)
        print("%-16s %6d bytes" % (name, len(data)))
    print("rom port oracle: %d ports, %d bytes -> %s"
          % (len(ports), total, dest))


if __name__ == "__main__":
    main()
