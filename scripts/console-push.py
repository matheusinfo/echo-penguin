#!/usr/bin/env python3
"""console-push.py — copy a file to the Echo over its USB serial console, for a unit without network
(rescue with no Wi-Fi driver or firmware yet). Base64 in short lines (the console's line discipline
takes at most 4095 bytes a line), decoded with busybox's base64, checked by md5. Slow (tens of KB/s):
for firmware and small trees, not root filesystems.

    scripts/console-push.py [--serial S] <local file> <remote path>
"""
import argparse
import base64
import hashlib
import os
import sys

BUILD = os.environ.get('PENGUIN_BUILD') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'echo-penguin-build')
sys.path.insert(0, os.path.join(BUILD, 'techo5', 'tools'))
from techo5lib import CONSOLE_TECHO5, Console  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--serial', default=os.environ.get('ECHO_SERIAL'),
                help="the unit's serial number (default: $ECHO_SERIAL)")
ap.add_argument('--chunk', type=int, default=2048, help='base64 characters a line')
ap.add_argument('local')
ap.add_argument('remote')
a = ap.parse_args()
if not a.serial:
    ap.error('pass --serial or set ECHO_SERIAL to the unit\'s serial number')

data = open(a.local, 'rb').read()
b64 = base64.b64encode(data).decode()
c = Console(a.serial, CONSOLE_TECHO5)
tmp = '/tmp/console-push.b64'
if c.run(': > %s && echo READY' % tmp, 10) is None:
    sys.exit('no answer from the USB console')
n = (len(b64) + a.chunk - 1) // a.chunk
for i in range(n):
    part = b64[i * a.chunk:(i + 1) * a.chunk]
    out = c.run("printf %%s '%s' >> %s && echo OK%d" % (part, tmp, i), 15)
    if out is None or 'OK%d' % i not in out:
        sys.exit('chunk %d of %d failed: %r' % (i + 1, n, out))
    if i % 50 == 0:
        print('  %s: %d/%d' % (os.path.basename(a.local), i + 1, n), file=sys.stderr)
want = hashlib.md5(data).hexdigest()
out = c.run("mkdir -p \"$(dirname '%s')\" && base64 -d %s > '%s' && rm -f %s && md5sum '%s'" % (a.remote, tmp, a.remote, tmp, a.remote), 30) or ''
if want not in out:
    sys.exit('md5 mismatch for %s: %r' % (a.remote, out))
print('%s -> %s (%d bytes, md5 ok)' % (a.local, a.remote, len(data)))
