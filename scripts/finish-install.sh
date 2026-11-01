#!/bin/bash
# finish-install.sh — finish an install that stopped at the slot store, on the unit's USB console.
#
#   scripts/finish-install.sh [--serial S] [--rootfs /data/media/0/Download/<file>.tar.gz]
#
# For a unit sitting in the rescue environment (RESCUE on screen, console on /dev/ttyACM*) after
# install.sh stopped at "slot store": the steps TECHO5's docs/install.md gives for "If the install stops
# at the slot store", each checked before the next:
#   1. keeps rescue up (/tmp/stay), checks the vendor tree saved in /data/techo5-linux/vendor.tar
#   2. slotctl mkstore on mmcblk0p12 (ERASES it: by now LineageOS is gone from it anyway)
#   3. the unit's vendor tree into the store
#   4. the rootfs install.sh pushed into slot a
#   5. the SSH key (SSH_PUB) on userdata, then removes vendor.tar once slot a has the vendor tree
#   6. reboots into slot a
. "$(dirname "$0")/lib.sh"

SERIAL=${ECHO_SERIAL:-}
RFS=
while [ $# -gt 0 ]; do
	case "$1" in
	--serial) SERIAL=$2; shift 2;;
	--rootfs) RFS=$2; shift 2;;
	*) die "unknown argument $1";;
	esac
done
[ -n "$SERIAL" ] || die "pass --serial or set ECHO_SERIAL to the unit's serial number"
systemctl is-active -q ModemManager 2>/dev/null && { systemctl stop ModemManager 2>/dev/null || die "stop ModemManager first"; }
C() { python3 "$PENGUIN/scripts/console.py" --serial "$SERIAL" --timeout "$1" "$2"; }
WLAN=vendor/lib/modules/mt76x8_wlan.ko

say "rescue console"
o=$(C 20 'touch /tmp/stay; echo slot=$(cat /run/techo5/slot 2>/dev/null)-') || die "no USB console from $SERIAL"
case "$o" in *slot=-*) note "rescue environment (no slot booted)";; *) die "the unit booted a slot already: $o";; esac
o=$(C 60 "tar -tf /data/techo5-linux/vendor.tar $WLAN >/dev/null && echo VENDOR-TAR-OK")
[[ "$o" == *VENDOR-TAR-OK* ]] || die "no usable /data/techo5-linux/vendor.tar on the unit: $o"
if [ -z "$RFS" ]; then
	RFS=$(C 20 'ls -t /data/media/0/Download/echo-penguin-rootfs-*.tar.gz 2>/dev/null | head -1' | tr -d '\r' | tail -1)
fi
[ -n "$RFS" ] || die "no echo-penguin rootfs in /data/media/0/Download (install.sh pushes it there)"
note "rootfs: $RFS"

say "slot store on mmcblk0p12 (erases it)"
o=$(C 20 'test -e /store/.techo5-store && echo HAVE-STORE')
if [[ "$o" == *HAVE-STORE* ]]; then
	note "a store is already there; not making it again"
else
	o=$(C 300 'umount /android 2>/dev/null; slotctl mkstore /dev/mmcblk0p12 --i-know-this-erases-it > /tmp/mkstore.log 2>&1 && echo MKSTORE-OK; tail -3 /tmp/mkstore.log')
	[[ "$o" == *MKSTORE-OK* ]] || die "mkstore failed: $o"
fi

say "vendor tree into the store"
o=$(C 180 "mountpoint -q /store || mount -t ext4 /dev/mmcblk0p12 /store; mount -o remount,rw /store; tar -xf /data/techo5-linux/vendor.tar -C /store && [ -e /store/$WLAN ] && echo VENDOR-OK")
[[ "$o" == *VENDOR-OK* ]] || die "vendor tree not in the store: $o"

say "rootfs into slot a (a few minutes, silent)"
o=$(C 900 "STORE=/store slotctl install '$RFS' > /tmp/install.log 2>&1 && echo INSTALL-OK; tail -2 /tmp/install.log; [ -e /store/slots/a/$WLAN ] && echo SLOT-VENDOR-OK; STORE=/store slotctl status")
[[ "$o" == *INSTALL-OK* ]] || die "slotctl install failed: $o"
[[ "$o" == *SLOT-VENDOR-OK* ]] || die "slot a has no vendor tree: $o"
echo "$o" | grep '^slot ' | sed 's/^/   /'

say "SSH key and clean-up"
pub=$(cat "$SSH_PUB")
o=$(C 30 "mkdir -p -m 700 /data/misc/techo5/ssh && (umask 077; printf '%s\n' '$pub' > /data/misc/techo5/ssh/authorized_keys) && mkdir -p /data/misc/techo5 && printf 'echo-penguin\n' > /data/misc/techo5/name && rm -f /data/techo5-linux/vendor.tar && sync && echo PROV-OK")
[[ "$o" == *PROV-OK* ]] || die "provisioning failed: $o"
note "key $(ssh-keygen -lf "$SSH_PUB" | cut -d' ' -f2) on the unit"

say "reboot into slot a"
C 5 'sync; (sleep 2; /bin/busybox.static reboot -f) >/dev/null 2>&1 &' >/dev/null || true
note "then: HOST=<address> scripts/verify.sh  (the slot commits itself after five healthy minutes)"
