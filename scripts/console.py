#!/usr/bin/env python3
"""console.py — run one shell command on the Echo through its USB serial console (the TECHO5 gadget,
1d6b:0104) and print the output: the way in when the unit has no network. Uses TECHO5's own Console
class (tools/techo5lib.py), as its installer does.

    scripts/console.py [--serial S] [--timeout SECONDS] 'command'
"""
import argparse
import os
import sys

BUILD = os.environ.get('PENGUIN_BUILD') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'echo-penguin-build')
sys.path.insert(0, os.path.join(BUILD, 'techo5', 'tools'))
from techo5lib import CONSOLE_TECHO5, Console  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--serial', default=os.environ.get('ECHO_SERIAL'),
                help="the unit's serial number (default: $ECHO_SERIAL)")
ap.add_argument('--timeout', type=int, default=30)
ap.add_argument('command')
a = ap.parse_args()
if not a.serial:
    ap.error('pass --serial or set ECHO_SERIAL to the unit\'s serial number')
out = Console(a.serial, CONSOLE_TECHO5).run(a.command, a.timeout)
if out is None:
    sys.exit('no answer from the USB console (is the unit up, and the port free?)')
print(out)
