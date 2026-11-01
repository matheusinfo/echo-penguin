# /lib/penguin.sh — echo-penguin's shared shell functions (sourced by boot.sh, the supervisor and
# the penguin command). busybox ash; everything best effort, nothing may stop the boot.

PENGUIN_DATA=/data/penguin
PENGUIN_LOGS=$PENGUIN_DATA/logs
# The Docker CLI keeps its config (buildx, logins) in ~/.docker; /root is on the read-only root.
export DOCKER_CONFIG=$PENGUIN_DATA/docker-cli

# p_settings: the image's defaults, then the unit's own overrides on userdata.
p_settings() {
	. /etc/penguin/defaults.conf
	[ -r $PENGUIN_DATA/settings.conf ] && . $PENGUIN_DATA/settings.conf
	return 0
}

# p_log <tag> <message...>: kernel log (pstore keeps it across a crash) and the boot log.
p_log() {
	tag=$1; shift
	echo "penguin-$tag: $*" > /dev/kmsg 2>/dev/null
	echo "$(cut -d' ' -f1 /proc/uptime) $tag: $*" >> /run/boot.log 2>/dev/null
	# On the screen too: the kernel console only shows errors once p_screen has run.
	[ -n "$P_SCREEN" ] && echo "$tag: $*" > /dev/tty1 2>/dev/null
	return 0
}

# p_screen: the panel's terminal (tty1, the framebuffer console). The kernel prints everything there
# until now; from here only messages more urgent than SCREEN_LOGLEVEL (default 4: errors and worse),
# since MediaTek's drivers log warnings every few seconds ("[WDK]: kick Ex WDT") and would scroll
# everything else away. echo-penguin's own events (p_log) and mirrored sessions go to tty1 directly.
p_screen() {
	[ -c /dev/tty1 ] || return 0
	dmesg -n "${SCREEN_LOGLEVEL:-4}" 2>/dev/null
	P_SCREEN=1
	printf '\n\033[1;36mecho-penguin\033[0m %s\n' "$(cat /etc/techo5-release 2>/dev/null)" > /dev/tty1 2>/dev/null
	return 0
}

# p_rotate <file>: keep a log under LOG_MAX bytes, one old generation beside it.
p_rotate() {
	[ -f "$1" ] && [ "$(stat -c %s "$1" 2>/dev/null || echo 0)" -gt "${LOG_MAX:-2000000}" ] && mv -f "$1" "$1.1"
	return 0
}

# p_docker_kernel: whether this kernel can run containers (the "docker" boot image).
p_docker_kernel() {
	[ -e /proc/self/ns/net ] && [ -e /proc/self/ns/pid ] && grep -qw cpuset /proc/cgroups 2>/dev/null
}

# p_cpus: bring the cores Android kept offline online (validated-hardware.md: 2 and 3).
p_cpus() {
	for c in ${CPU_ONLINE:-}; do
		f=/sys/devices/system/cpu/cpu$c/online
		[ -w $f ] && [ "$(cat $f)" != 1 ] && { echo 1 > $f 2>/dev/null || p_log hw "cpu$c would not come online"; }
	done
	p_log hw "cpus online: $(cat /sys/devices/system/cpu/online 2>/dev/null)"
}

# p_zram: swap in zram (CONFIG_ZRAM=y), lz4 when the kernel has it.
p_zram() {
	[ "${ZRAM_MB:-0}" -gt 0 ] 2>/dev/null || return 0
	grep -q zram0 /proc/swaps && return 0
	[ -e /sys/block/zram0 ] || { p_log hw "no zram0"; return 0; }
	grep -qw lz4 /sys/block/zram0/comp_algorithm 2>/dev/null && echo lz4 > /sys/block/zram0/comp_algorithm
	echo $((ZRAM_MB * 1024 * 1024)) > /sys/block/zram0/disksize 2>/dev/null &&
		mkswap /dev/zram0 >/dev/null 2>&1 && swapon -p 10 /dev/zram0 2>/dev/null &&
		p_log hw "zram swap ${ZRAM_MB} MB" || p_log hw "zram swap failed"
	echo 60 > /proc/sys/vm/swappiness 2>/dev/null
}

# p_cgroups: cgroup v1 hierarchies, one per controller, as Docker on a 4.x kernel expects
# (cgroupfs-mount). Done on every kernel: harmless where there is nothing to mount.
p_cgroups() {
	mountpoint -q /sys/fs/cgroup || mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup || return 0
	for c in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
		mkdir -p /sys/fs/cgroup/$c
		mountpoint -q /sys/fs/cgroup/$c || mount -t cgroup -o $c cgroup /sys/fs/cgroup/$c 2>/dev/null ||
			p_log hw "cgroup $c not mounted"
	done
	# memory.use_hierarchy, as systemd and cgroupfs-mount set it.
	[ -w /sys/fs/cgroup/memory/memory.use_hierarchy ] && echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy 2>/dev/null
	p_log hw "cgroups: $(ls /sys/fs/cgroup | tr '\n' ' ')"
}

# p_backlight: the panel at the configured level; BACKLIGHT=0 turns it off. Backlight 0 alone is not
# enough on cronos (the panel keeps the last picture), so then the framebuffer is cleared and the panel
# blanked too (measured on the unit, 2026-10-31). Otherwise the framebuffer console owns the screen.
p_backlight() {
	f=/sys/class/leds/lcd-backlight/brightness
	if [ "${BACKLIGHT:-90}" = 0 ] && [ -w /dev/fb0 ]; then
		dd if=/dev/zero of=/dev/fb0 bs=64k 2>/dev/null
		echo 1 > /sys/class/graphics/fb0/blank 2>/dev/null
	else
		echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
	fi
	[ -w $f ] && echo "${BACKLIGHT:-90}" > $f 2>/dev/null && p_log hw "backlight ${BACKLIGHT:-90}"
	return 0
}

# p_watchdog: busybox's watchdog daemon on the MT8163 watchdog (plan, Stage 8.2). If userspace hangs
# and stops feeding it, the SoC resets. Skipped when something (the initramfs, for the boot layer)
# already holds it.
p_watchdog() {
	[ "${WATCHDOG:-0}" = 1 ] || return 0
	pidof watchdog >/dev/null && return 0
	for d in /dev/watchdog0 /dev/watchdog; do
		[ -c $d ] || continue
		watchdog -t 10 -T 60 $d 2>/dev/null && { p_log hw "watchdog on $d"; return 0; }
	done
	p_log hw "no watchdog device"
}

# p_temp: CPU temperature in whole degrees C (mtktscpu), empty when unreadable.
p_temp() {
	t=$(cat /sys/class/thermal/thermal_zone${TEMP_ZONE:-12}/temp 2>/dev/null) || return 0
	[ -n "$t" ] && echo $((t / 1000))
}

# p_wifi_module: on the docker kernel LineageOS's mt76x8_wlan.ko no longer fits (its symbol CRCs
# changed), so the driver rebuilt for this kernel is put where t5_wifi_up looks first:
# /lib/modules/<release>/extra. On the safe kernel nothing is done and the vendor module loads.
p_wifi_module() {
	p_docker_kernel || return 0
	m=/usr/lib/penguin/modules/docker/mt76x8_wlan.ko
	[ -e $m ] || { p_log wifi "docker kernel but no rebuilt driver in the image; Wi-Fi will fail"; return 0; }
	d=/run/penguin/modules/$(uname -r)/extra
	mkdir -p $d && cp $m $d/ && mount --bind /run/penguin/modules /lib/modules &&
		p_log wifi "docker kernel: using the rebuilt mt76x8_wlan.ko" ||
		p_log wifi "could not stage the rebuilt driver"
}

# p_ssh: dropbear, keys only, whenever a key is on userdata. TECHO5's daemon used to decide this
# from Home Assistant; here SSH is the way in, so it is always on (plan, Stage 5.2).
p_ssh() {
	keys=/data/misc/techo5/ssh/authorized_keys
	if [ ! -s $keys ]; then
		p_log ssh "no key in $keys; SSH stays off (USB serial console only)"
		return 0
	fi
	chmod 700 /data/misc/techo5/ssh; chmod 600 $keys
	# -s: no password logins at all; -g: none for root either. Local forwarding stays on, for SSH
	# tunnels to services on the unit (ssh -L).
	t5_dropbear /data/techo5-linux/dropbear -s -g
}
