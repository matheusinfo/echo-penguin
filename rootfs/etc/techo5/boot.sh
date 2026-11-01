#!/bin/sh
# echo-penguin root filesystem: sysinit (see /etc/inittab).
#
# A trimmed fork of TECHO5's etc/techo5/boot.sh (same path, so TECHO5's initramfs, slotctl and
# installer work unchanged). Kept: the mounts, crash records, the vendor tree in the store, the USB
# serial console, the firewall, Wi-Fi, NTP, the network keeper and the slot trial. Dropped: voice,
# Bluetooth, the mainline/athena branches and the kernel updater. Added: the hardware set-up from
# validated-hardware.md (cores, zram, cgroups, backlight, watchdog) and SSH that is always on when a
# key is on userdata.
#
# The initramfs hands over with /proc, /sys, /dev, /run, /tmp, /data and /store (read-only) mounted
# and the booted slot's name in /run/techo5/slot. Everything is best effort and logged: nothing may
# keep the supervisor (/usr/local/bin/techo5, started by inittab) from starting.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
LOGDIR=/data/techo5-linux
log() { echo "techo5-boot: $*" > /dev/kmsg; echo "$(cut -d' ' -f1 /proc/uptime) $*" >> /run/boot.log; [ -n "$P_SCREEN" ] && echo "$*" > "$P_SCREEN" 2>/dev/null; return 0; }

DATA_DEV=/dev/mmcblk0p16
STORE_DEV=/dev/mmcblk0p12
WIFI_MODULE=/vendor/lib/modules/mt76x8_wlan.ko
WIFI_SDIO_HOST=
[ -r /etc/techo5/device.conf ] && . /etc/techo5/device.conf
. /lib/techo5-lib.sh
. /lib/penguin.sh

# --- Mounts the initramfs normally provides, for a boot that did not come through it.
mountpoint -q /proc || mount -t proc proc /proc
mount -o remount,hidepid=2 /proc 2>/dev/null || log "proc: hidepid=2 refused"
mountpoint -q /sys || mount -t sysfs sysfs /sys
if ! mountpoint -q /dev; then
	mount -t tmpfs -o mode=0755 tmpfs /dev
	mkdir -p /dev/pts
	mount -t devpts devpts /dev/pts
fi
mountpoint -q /run || mount -t tmpfs tmpfs /run
mountpoint -q /tmp || mount -t tmpfs tmpfs /tmp
mkdir -p /dev/shm
mountpoint -q /dev/shm || mount -t tmpfs -o mode=1777,size=16m tmpfs /dev/shm
mountpoint -q /data || mount -t ext4 -o noatime $DATA_DEV /data
mountpoint -q /store || mount -t ext4 -o ro,noatime $STORE_DEV /store
# The root is read-only; what needs writing lives on tmpfs or userdata.
mount -t tmpfs tmpfs /var/log
mount -t tmpfs tmpfs /var/tmp
mkdir -p /run/lock /run/techo5 /run/penguin $LOGDIR $PENGUIN_LOGS /data/misc/techo5
p_settings
[ -e /run/hosts ] || printf '127.0.0.1\tlocalhost localhost.localdomain\n::1\t\tlocalhost localhost.localdomain\n' > /run/hosts
# Clock zone on userdata (TECHO5's layout); the image's default the first time.
if [ ! -e /data/misc/techo5/timezone ] || [ ! -e /data/misc/techo5/localtime ]; then
	zone=$(cat /etc/techo5/default-timezone 2>/dev/null || echo UTC)
	[ -e "/usr/share/zoneinfo/$zone" ] || zone=UTC
	ln -sfn "/usr/share/zoneinfo/$zone" /data/misc/techo5/localtime
	echo "$zone" > /data/misc/techo5/timezone
fi
mkdir -p -m 700 /data/misc/techo5/ssh
# Kernel crash records (pstore) copied to userdata, the newest 20 kept.
if mount -t pstore pstore /sys/fs/pstore 2>/dev/null || [ -d /sys/fs/pstore ]; then
	n=
	for f in /sys/fs/pstore/*; do
		[ -e "$f" ] || continue
		mkdir -p $LOGDIR/crash
		[ -n "$n" ] || { n=$(($(cat $LOGDIR/crash/.count 2>/dev/null || echo 0) + 1)); echo $n > $LOGDIR/crash/.count; }
		cp "$f" "$LOGDIR/crash/$(printf %05d $n)-${f##*/}" 2>/dev/null && log "kernel crash record kept: ${f##*/}" && rm -f "$f"
	done
	ls -1 $LOGDIR/crash/[0-9][0-9][0-9][0-9][0-9]-* 2>/dev/null | sort -r | tail -n +21 | while read -r f; do rm -f "$f"; done
fi
: > /run/boot.log

echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s
chmod 666 /dev/null /dev/zero /dev/full /dev/random /dev/urandom /dev/tty 2>/dev/null
hostname -F /etc/hostname
p_screen
log "slot $(cat /run/techo5/slot 2>/dev/null || echo '?'): $(cat /etc/techo5-release 2>/dev/null)"

# --- Hardware (validated-hardware.md): all four cores, zram swap, cgroups for Docker, screen, sound,
# watchdog. Before the network so a hang from here on is caught by the watchdog.
p_cpus
p_zram
p_cgroups
p_backlight
p_audio
p_watchdog

# --- Vendor tree: LineageOS's Wi-Fi firmware and modules, kept once in the store (TECHO5's scheme:
# the installer put it there) and bound at /vendor.
VMOD=${WIFI_MODULE#/vendor/}
if [ ! -e "/store/vendor/$VMOD" ]; then
	src=
	for d in /vendor /store/slots/a/vendor /store/slots/b/vendor; do
		[ -e "$d/$VMOD" ] && { src=$d; break; }
	done
	if [ -z "$src" ]; then
		log "vendor tree: none on this unit; no Wi-Fi"
	elif mount -o remount,rw /store; then
		rm -rf /store/vendor.new
		if cp -a "$src" /store/vendor.new && [ -e "/store/vendor.new/$VMOD" ]; then
			rm -rf /store/vendor && mv /store/vendor.new /store/vendor && log "vendor tree: kept in the store, from $src"
		else
			rm -rf /store/vendor.new
			log "vendor tree: copying $src into the store failed"
		fi
		sync
		mount -o remount,ro /store || log "vendor tree: the store stayed writable"
	fi
fi
if [ ! -e "$WIFI_MODULE" ] && [ -e "/store/vendor/$VMOD" ]; then
	mkdir -p /vendor 2>/dev/null
	mount --bind /store/vendor /vendor && log "vendor tree: /vendor is the store's"
fi
# The docker kernel needs the driver rebuilt for it (the vendor one no longer loads).
p_wifi_module

# --- Root shell on USB serial (techo5-console attaches to it).
t5_usb_acm

# --- Inbound on Wi-Fi closed except SSH (and LAN_PORTS), before any network.
/usr/local/sbin/techo5-firewall > $LOGDIR/firewall.log 2>&1

# --- Network. Credentials: the file on userdata, first written from Android's saved network.
t5_wifi_conf $LOGDIR/wpa_supplicant.conf
export UDHCPC_SCRIPT=/etc/techo5/udhcpc.sh
t5_wifi_up $WIFI_MODULE $LOGDIR/wpa_supplicant.conf
p_ssh
if [ -n "$IP" ]; then
	t5_ntp
	ntpd -S /etc/techo5/ntp-event.sh $(t5_ntp_peers) > /dev/null 2>&1
fi

# --- Network keeper: bring Wi-Fi back if it is gone, and reboot after 15 minutes without an
# address: an unattended unit must never sit unreachable (plan, Stage 5).
(
	down=0; lost=0
	while true; do
		sleep 60
		if t5_wifi_joined; then lost=0; else lost=$((lost+1)); fi
		if [ -n "$(t5_ip)" ] && [ $lost -lt 3 ]; then
			down=0
			if ! ip route show default 2>/dev/null | grep -q default; then
				log "network: address but no default route; renewing the lease"
				if [ -x /usr/local/sbin/techo5-net ]; then
					/usr/local/sbin/techo5-net renew
				else
					killall udhcpc 2>/dev/null
					udhcpc -i wlan0 -b -R -t 10 -p /run/udhcpc.pid -s "$UDHCPC_SCRIPT" > /tmp/udhcpc.log 2>&1
				fi
			fi
			if [ "$(date +%Y)" -lt 2020 ] && pidof ntpd >/dev/null; then
				killall ntpd 2>/dev/null
				sleep 1
			fi
			if ! pidof ntpd >/dev/null; then
				t5_ntp
				ntpd -S /etc/techo5/ntp-event.sh $(t5_ntp_peers) > /dev/null 2>&1
			fi
			pidof dropbear >/dev/null || p_ssh
			[ -x /usr/local/sbin/techo5-net ] && /usr/local/sbin/techo5-net check
			t5_wifi_prefer5
			continue
		fi
		if ! grep -q '^network={' $LOGDIR/wpa_supplicant.conf 2>/dev/null; then
			down=0
			pidof wpa_supplicant >/dev/null || t5_wifi_up $WIFI_MODULE $LOGDIR/wpa_supplicant.conf
			continue
		fi
		down=$((down+1))
		if [ $lost -ge 3 ]; then
			log "network: not associated for $lost min, down for $down"
		else
			log "network: no address for $down min"
		fi
		if [ $down -ge 15 ]; then
			log "network: rebooting"
			cp /run/boot.log $LOGDIR/boot.log 2>/dev/null
			sync
			reboot
		fi
		killall udhcpc wpa_supplicant 2>/dev/null
		rm -f /run/techo5/prefer5-pin /run/techo5/prefer5-pin.miss
		n=0; while [ $n -lt 10 ] && pidof wpa_supplicant >/dev/null; do sleep 1; n=$((n+1)); done
		t5_wifi_up $WIFI_MODULE $LOGDIR/wpa_supplicant.conf
	done
) &

# --- Slot trial (TECHO5's): the slot is committed once the supervisor (named techo5, as slotctl
# and the installer expect) has run for TRIAL_SETTLE seconds and, with TRIAL_NEEDS_NETWORK=1
# (etc/techo5/trial.conf), there is a default route. A boot that never gets there reboots at
# TRIAL_TIMEOUT to use up a try; after three the initramfs falls back to the other slot.
TRIAL_SETTLE=${TRIAL_SETTLE:-300}
TRIAL_TIMEOUT=${TRIAL_TIMEOUT:-900}
TRIAL_NEEDS_NETWORK=${TRIAL_NEEDS_NETWORK:-0}
[ -r /etc/techo5/trial.conf ] && . /etc/techo5/trial.conf
trial_network() {
	[ "$TRIAL_NEEDS_NETWORK" = 1 ] || return 0
	ip route show default 2>/dev/null | grep -q default
}
on_trial() {
	case "$(cat /store/slots/$1.state 2>/dev/null)" in trial*) return 0;; esac
	[ "$(t5_ab_slot)" = "$1" ] && bootctl -q status 2>/dev/null | grep -q "^slot $1: .*successful 0"
}
(
	s=$(cat /run/techo5/slot 2>/dev/null)
	[ -n "$s" ] || exit 0
	on_trial "$s" || exit 0
	while true; do
		sleep 15
		now=$(cut -d. -f1 /proc/uptime)
		pid=$(pidof techo5 | cut -d' ' -f1)
		if [ -n "$pid" ]; then
			started=$(awk '{print int($22/100)}' /proc/$pid/stat 2>/dev/null)
			if [ -n "$started" ] && [ $((now-started)) -ge $TRIAL_SETTLE ] && trial_network; then
				log "slot $s: supervisor up for $TRIAL_SETTLE s, committing"
				slotctl commit >> /run/boot.log 2>&1
				exit 0
			fi
		fi
		if [ $now -ge $TRIAL_TIMEOUT ]; then
			log "slot $s: not settled within $TRIAL_TIMEOUT s; rebooting to use up a try"
			cp /run/boot.log $LOGDIR/boot.log 2>/dev/null
			sync
			reboot
		fi
	done
) &

cp /run/boot.log $LOGDIR/boot.log 2>/dev/null
log "boot script done"
