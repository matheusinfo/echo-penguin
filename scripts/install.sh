#!/bin/bash
# install.sh — first install on a unit running LineageOS: TECHO5's installer with echo-penguin's images.
#
#   scripts/install.sh [safe|docker] [install-show.py options...]
#   e.g. scripts/install.sh safe --dry-run
#        scripts/install.sh safe --serial <serial>
#
# tools/install-show.py does every step and checks each before the next (its docstring): unit and
# kernel checks, the LineageOS boot image backup, the push, `fastboot flash boot`, the slot store on
# mmcblk0p12 (THIS ERASES LINEAGEOS's system partition, after one confirmation), the unit's own vendor
# tree, slot a, the SSH key, and the first boot. It asks before erasing anything.
#
# safe is the default and the recommended first install: LineageOS's own Wi-Fi driver, no Docker. The docker kernel goes on afterwards with flash-boot.sh, which falls back by itself.
. "$(dirname "$0")/lib.sh"

VARIANT=safe
case "${1:-}" in safe|docker) VARIANT=$1; shift;; esac
BOOT=$OUT/echo-penguin-boot-$VARIANT.img
ROOTFS=$(ls -t "$OUT"/echo-penguin-rootfs-*.tar.gz 2>/dev/null | head -1)
[ -e "$BOOT" ] || die "no $BOOT: run build-boot.sh $VARIANT"
[ -n "$ROOTFS" ] || die "no rootfs in $OUT: run build-rootfs.sh"
[ -e "$SSH_PUB" ] || die "no SSH public key at $SSH_PUB"
if [ "$VARIANT" = docker ]; then
	tar -tzf "$ROOTFS" ./usr/lib/penguin/modules/docker/mt76x8_wlan.ko >/dev/null 2>&1 ||
		die "$ROOTFS has no Wi-Fi driver for the docker kernel; rebuild it after build-kernel.sh docker"
fi
say "installing echo-penguin ($VARIANT kernel)"
note "boot:   $BOOT"
note "rootfs: $ROOTFS"
note "ssh:    $SSH_PUB"
# ModemManager probes new USB serial ports with AT commands and can hold the unit's console, which the
# installer needs once it has flashed; TECHO5's installer refuses to start while it runs. Stopped for
# this boot of the computer (polkit usually allows it for a desktop user; it is back after a reboot).
if systemctl is-active -q ModemManager 2>/dev/null; then
	systemctl stop ModemManager 2>/dev/null || sudo systemctl stop ModemManager ||
		die "ModemManager is running and could not be stopped: sudo systemctl stop ModemManager"
	note "ModemManager stopped until the next reboot of this computer"
fi
# The backups the earlier TECHO5 install made (LineageOS boot image, partitions, key) are reused, so
# the run does not take them again; TECHO5_BACKUPS= overrides.
BACKUPS=${TECHO5_BACKUPS:-$ROOT/../echo-show/techo5/backups}
[ -d "$BACKUPS" ] || BACKUPS=$TECHO5/backups
note "backups: $BACKUPS"
cd "$TECHO5"
exec python3 tools/install-show.py --name echo-penguin --boot "$BOOT" --rootfs "$ROOTFS" --ssh-key "$SSH_PUB" \
	--backups "$BACKUPS" --work "$WORK/installer" "$@"
