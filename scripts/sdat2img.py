#!/usr/bin/env python3
"""sdat2img.py — LineageOS system.transfer.list + system.new.dat(.br) -> system.img (ext4), so the vendor
modules can be read with debugfs. Minimal: handles the new/erase/zero commands of transfer list v4."""
import sys, brotli
tl, dat, out = sys.argv[1:4]
lines = open(tl).read().split('\n')
ver = int(lines[0]); cmds = lines[4:] if ver >= 2 else lines[2:]
def rng(s):
    v = list(map(int, s.split(','))); return [(v[i], v[i+1]) for i in range(1, len(v), 2)]
data = brotli.decompress(open(dat, 'rb').read()) if dat.endswith('.br') else open(dat, 'rb').read()
BS = 4096; off = 0; maxb = 0
news = []
for c in cmds:
    p = c.split(' ')
    if p[0] == 'new':
        for a, b in rng(p[1]): news.append((a, b)); maxb = max(maxb, b)
    elif p[0] in ('erase', 'zero'):
        for a, b in rng(p[1]): maxb = max(maxb, b)
with open(out, 'wb') as f:
    f.truncate(maxb * BS)
    for a, b in news:
        n = (b - a) * BS
        f.seek(a * BS); f.write(data[off:off + n]); off += n
print('wrote', out, maxb * BS, 'bytes; used', off, 'of', len(data))
