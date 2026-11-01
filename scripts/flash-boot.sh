#!/bin/bash
# flash-boot.sh — switch an installed unit's kernel (boot partition) between safe and docker.
#
#   HOST=<echo address> scripts/flash-boot.sh safe|docker [--serial <fastboot serial>]
#
# Over SSH the unit reboots into fastboot (rebootto bootloader); over USB the boot image is flashed and
# the unit started. Then it waits up to five minutes for SSH. The boot partition is not slotted, so a
# kernel whose Wi-Fi fails does not fall back on its own: when SSH does not come back, this flashes the
# previous boot image again (fastboot is still reachable by holding the unit in the bootloader, see
# README "Way back"). Keep the USB cable in for the whole run.
. "$(dirname "$0")/lib.sh"

VARIANT=${1:-}; shift || true
case "$VARIANT" in safe|docker) ;; *) die "usage: HOST=... flash-boot.sh safe|docker [--serial S]";; esac
SERIAL=
[ "${1:-}" = --serial ] && SERIAL=$2
HOST=${HOST:-}
[ -n "$HOST" ] || die "set HOST=<the unit's address>"
IMG=$OUT/echo-penguin-boot-$VARIANT.img
[ -e "$IMG" ] || die "no $IMG: run build-boot.sh $VARIANT"
FB=(fastboot ${SERIAL:+-s "$SERIAL"})
# The fallback talks to the unit's USB serial console; ModemManager would probe and hold it.
systemctl is-active -q ModemManager 2>/dev/null && { systemctl stop ModemManager 2>/dev/null || note "ModemManager is running: the console fallback may not reach the unit"; }
SSH=(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "root@$HOST")

if [ "$VARIANT" = docker ]; then
	"${SSH[@]}" 'test -e /usr/lib/penguin/modules/docker/mt76x8_wlan.ko' ||
		die "the unit's rootfs has no Wi-Fi driver for the docker kernel: install a rootfs built after build-kernel.sh docker first"
fi
was=$("${SSH[@]}" 'grep -qw cpuset /proc/cgroups && echo docker || echo safe') || die "no SSH to $HOST"
say "unit runs the $was kernel; flashing $VARIANT"
PREV=$OUT/echo-penguin-boot-$was.img

flash() { # image
	"${SSH[@]}" 'PATH=$PATH:/usr/local/sbin:/usr/local/bin; rebootto bootloader' >/dev/null 2>&1 || true
	n=0; until "${FB[@]}" devices 2>/dev/null | grep -q fastboot; do
		n=$((n+1)); [ $n -ge 60 ] && die "the unit did not reach fastboot (USB cable in?)"; sleep 2
	done
	"${FB[@]}" flash boot "$1" && "${FB[@]}" continue
}
ssh_back() {
	n=0; until "${SSH[@]}" true 2>/dev/null; do
		n=$((n+1)); [ $n -ge 60 ] && return 1; sleep 5
	done
}

flash "$IMG"
say "waiting for SSH (up to five minutes)"
if ssh_back; then
	"${SSH[@]}" 'PATH=$PATH:/usr/local/sbin:/usr/local/bin; uname -a; penguin status | head -12'
	say "done: the $VARIANT kernel is up"
	exit 0
fi
note "no SSH after five minutes on the $VARIANT kernel"
# The unit is most likely up without Wi-Fi: its USB serial console (the TECHO5 gadget, 1d6b:0104)
# still answers, so it is told to go to fastboot from there. Only that device is written to.
console_to_fastboot() {
	for tty in /sys/class/tty/ttyACM*; do
		[ -e "$tty" ] || continue
		dev=$(readlink -f "$tty/device/..")
		[ "$(cat "$dev/idVendor" 2>/dev/null):$(cat "$dev/idProduct" 2>/dev/null)" = 1d6b:0104 ] || continue
		note "asking the unit's USB console (/dev/${tty##*/}) for fastboot"
		printf '\nrebootto bootloader\n' > "/dev/${tty##*/}" 2>/dev/null ||
			note "/dev/${tty##*/} is not writable (add yourself to the dialout group)"
	done
}
if [ -e "$PREV" ] && [ "$PREV" != "$IMG" ]; then
	note "putting the $was kernel back"
	console_to_fastboot
	n=0; until "${FB[@]}" devices 2>/dev/null | grep -q fastboot; do
		n=$((n+1)); [ $n -ge 90 ] && die "no fastboot: README \"Way back\" (USB console: rebootto bootloader)"; sleep 2
	done
	"${FB[@]}" flash boot "$PREV" && "${FB[@]}" continue
	ssh_back && die "the $VARIANT kernel did not come up; the $was kernel is back (logs: penguin logs boot)"
fi
die "the unit is not reachable; README \"Way back\""
