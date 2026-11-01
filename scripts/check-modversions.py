#!/usr/bin/env python3
"""Check that binary vendor modules still load on a kernel built from source.

The MT7668 Wi-Fi and Bluetooth modules from LineageOS are binary-only and were built with
CONFIG_MODVERSIONS: the kernel refuses any module whose imported symbol CRCs (and the CRC of
module_layout) differ from its own. Kernel options such as NET_NS or CPUSETS change the layout of
core structures, which changes those CRCs, so a Docker-capable kernel can silently cost the unit its
Wi-Fi. This compares each module's __versions table against the build's Module.symvers.

    check-modversions.py <Module.symvers> <module.ko>...

Exit status 0 when every module matches, 1 otherwise.
"""
import struct
import sys


def symvers(path):
    crcs = {}
    with open(path) as f:
        for line in f:
            parts = line.split('\t')
            if len(parts) >= 2:
                crcs[parts[1]] = int(parts[0], 16)
    return crcs


def module_versions(path):
    """(crc, name) pairs from an ELF64 little-endian module's __versions section."""
    data = open(path, 'rb').read()
    if data[:4] != b'\x7fELF' or data[4] != 2:
        raise SystemExit('%s: not an ELF64 module' % path)
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    sections = []
    for i in range(shnum):
        name, _, _, _, off, size = struct.unpack_from('<IIQQQQ', data, shoff + i * shentsize)
        sections.append((name, off, size))
    stroff = sections[shstrndx][1]
    for name, off, size in sections:
        end = data.index(b'\0', stroff + name)
        if data[stroff + name:end] == b'__versions':
            out = []
            for p in range(off, off + size, 64):  # struct modversion_info: u64 crc + char name[56]
                crc, = struct.unpack_from('<Q', data, p)
                sym = data[p + 8:p + 64].split(b'\0')[0].decode()
                out.append((crc & 0xffffffff, sym))
            return out
    raise SystemExit('%s: no __versions section' % path)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    crcs = symvers(sys.argv[1])
    ok = True
    for ko in sys.argv[2:]:
        bad, missing, total = [], [], 0
        for crc, sym in module_versions(ko):
            total += 1
            # module_layout is exported by kernel/module.c, so it is in Module.symvers too: its CRC
            # covers struct module and friends, the first thing the loader checks.
            if sym not in crcs:
                missing.append(sym)
            elif crcs[sym] != crc:
                bad.append(sym)
        status = 'OK' if not bad and not missing else 'MISMATCH'
        print('%s: %s (%d symbols, %d differ, %d missing)' % (ko, status, total, len(bad), len(missing)))
        for s in bad[:40]:
            print('   differs: %s' % s)
        for s in missing[:40]:
            print('   missing: %s' % s)
        ok = ok and status == 'OK'
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
