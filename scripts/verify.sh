#!/bin/bash
# verify.sh — check an installed unit against the acceptance criteria (plan-echo-show-5.md, Stage 9).
#
#   HOST=<echo address> scripts/verify.sh
#
# Everything that can be checked now is checked from this computer, over SSH and the network; each line
# says PASS, FAIL or WARN. What needs hours (24 h healthy, 72 h without restarts) or a hand on the unit
# (power cut, rollback) is printed at the end as a checklist, with the command that shows it.
# Exit status: the number of FAILs.
. "$(dirname "$0")/lib.sh"

HOST=${HOST:-}
[ -n "$HOST" ] || die "set HOST=<the unit's address>"
SSH=(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o BatchMode=yes "root@$HOST")
fails=0
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails+1)); }
warn() { printf '  WARN  %s\n' "$*"; }
on() { "${SSH[@]}" "$@" 2>/dev/null; }

say "echo-penguin at $HOST"
on true || { fail "SSH with $SSH_KEY"; exit 1; }
pass "SSH by key ($SSH_KEY)"
if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o BatchMode=yes -o PubkeyAuthentication=no \
	-o PreferredAuthentications=password,keyboard-interactive "root@$HOST" true 2>/dev/null; then
	fail "a password login was accepted"
else
	pass "password logins refused"
fi

eval "$(on '. /lib/penguin.sh; p_settings
	echo "rel=\"$(cat /etc/techo5-release)\""
	echo "kern=$(p_docker_kernel && echo docker || echo safe)"
	echo "docker=$(cat /run/penguin/docker 2>/dev/null)"
	echo "slot=$(cat /run/techo5/slot 2>/dev/null)"
	echo "slotstate=\"$(cat /store/slots/$(cat /run/techo5/slot 2>/dev/null).state 2>/dev/null)\""
	echo "wlan=$(grep -c "^mt76x8_wlan " /proc/modules)"
	echo "cpus=$(cat /sys/devices/system/cpu/possible)"
	echo "hps=$(cat /proc/hps/enabled 2>/dev/null)"
	echo "avail=$(awk "/MemAvailable/ {print int(\$2/1024)}" /proc/meminfo)"
	echo "zram=$(grep -c zram0 /proc/swaps)"
	echo "temp=$(p_temp)"
	echo "wd=$(pidof watchdog >/dev/null && echo 1 || echo 0)"
	echo "dropbear=$(pidof dropbear >/dev/null && echo 1 || echo 0)"
	echo "sshopts=\"$(ps -o args | grep "^dropbear -R" | head -1)\""
	echo "sshallow=\"$SSH_ALLOW\""
	echo "dinfo=\"$(docker info --format "{{.Driver}} cgroup-v{{.CgroupVersion}} {{.ServerVersion}}" 2>/dev/null)\""
	echo "lan=\"$LAN_PORTS\" dlan=$DOCKER_LAN"
	echo "uptime=$(cut -d. -f1 /proc/uptime)"
	# Only dmesg-ramoops records are panics; console-ramoops is the console of every reboot, clean ones too.
	echo "crashes=$(ls /data/techo5-linux/crash 2>/dev/null | grep -c "^[0-9]*-dmesg-ramoops")"
	echo "rofs=$(grep -c " / .*ro[ ,]" /proc/mounts)"
	echo "ui=$(ps | grep -c "[p]enguin-ui")"
	echo "touch=$(grep -c "^N: Name=\"goodix-ts\"" /proc/bus/input/devices)"
	echo "fbcon=$(grep -c "frame buffer" /sys/class/vtconsole/vtcon*/name 2>/dev/null | grep -c ":1")"
	echo "vol=$(/usr/local/sbin/penguin-sound volume 2>/dev/null)"
	echo "espeak=$(command -v espeak-ng >/dev/null && echo 1 || echo 0)"
	echo "sleepd=$(/usr/local/sbin/penguin-sleep nights --json >/dev/null 2>&1 && echo 1 || echo 0)"
	echo "wxplace=\"$WEATHER_PLACE\" wxlat=\"$WEATHER_LAT\""
	echo "wxline=\"$(/usr/local/sbin/penguin-weather line 2>/dev/null | tr -d "\"\\$\`")\""')"

note "release: $rel"
note "kernel: $kern, docker: ${docker:-?}, slot ${slot:-none} ($slotstate)"
[ -n "$slot" ] && pass "booted from slot $slot" || fail "running the rescue environment, not a slot"
case "$slotstate" in good) pass "slot committed (good)";; trial*) warn "slot still on trial ($slotstate): commits after 5 healthy minutes";; *) fail "slot state '$slotstate'";; esac
[ "$wlan" = 1 ] && pass "Wi-Fi driver loaded (mt76x8_wlan)" || fail "mt76x8_wlan not loaded"
# MediaTek's hotplug (/proc/hps) takes idle cores offline and brings them back under load, so the
# number online at any moment says nothing; all four must exist and hps must be on.
[ "$cpus" = 0-3 ] && [ "${hps:-1}" = 1 ] && pass "four cores, MediaTek hotplug on" || warn "cores: $cpus, hotplug: ${hps:-?}"
missing=
for o in "-s" "-g" "-T 3" "-k"; do
	case " $sshopts " in *" $o "*) ;; *) missing="$missing $o";; esac
done
[ -z "$missing" ] && pass "dropbear: keys only, 3 tries, no remote forwarding" ||
	fail "dropbear options: '$sshopts' (missing$missing)"
[ -n "$sshallow" ] && pass "SSH limited to: $sshallow" ||
	warn "SSH open to any device on the Wi-Fi (key still required): penguin ssh allow here"
[ "${fbcon:-0}" -ge 1 ] && pass "screen console (fbcon)" || fail "no framebuffer console: the screen shows nothing"
if [ "${SCREEN_UI_EXPECTED:-1}" = 1 ]; then
	[ "${ui:-0}" = 1 ] && pass "touch interface running" || fail "penguin-ui is not running (${ui:-0} instances)"
fi
[ "${touch:-0}" = 1 ] && pass "touchscreen present (goodix-ts)" || fail "no goodix-ts input device"
case "$vol" in [0-9]*) pass "speaker volume control: $vol %";; *) fail "no speaker volume control (penguin-sound volume)";; esac
[ "${espeak:-0}" = 1 ] && pass "speech (espeak-ng)" || warn "espeak-ng missing: no speech after an alarm"
[ "${sleepd:-0}" = 1 ] && pass "sleep diary readable (penguin-sleep)" || warn "penguin-sleep nights failed"
if [ -n "$wxlat" ]; then
	[ -n "$wxline" ] && pass "weather for ${wxplace:-$wxlat}: $wxline" || warn "weather set (${wxplace:-$wxlat}) but no recent forecast (penguin-weather show)"
fi
[ "${avail:-0}" -ge 150 ] && pass "memory available: ${avail} MB" || fail "memory available: ${avail} MB (< 150)"
[ "$zram" = 1 ] && pass "zram swap active" || warn "no zram swap"
[ "$wd" = 1 ] && pass "watchdog fed" || warn "watchdog not running"
[ "$rofs" -ge 1 ] && pass "root filesystem read-only" || warn "root filesystem is writable"
if [ -n "$temp" ]; then
	[ "$temp" -lt 75 ] && pass "CPU ${temp}C (< 75)" || warn "CPU ${temp}C (>= 75)"
else
	warn "temperature unreadable"
fi
if [ "$kern" = docker ]; then
	if [ -n "$dinfo" ]; then
		pass "dockerd answers: $dinfo"
		case "$dinfo" in overlay2*) pass "storage driver overlay2";; *) warn "storage driver: ${dinfo%% *} (overlay2 expected)";; esac
	else
		[ "$docker" = off ] && warn "docker kernel but DOCKER=off" || fail "dockerd not answering (penguin logs docker)"
	fi
else
	note "safe kernel: no containers (switch with flash-boot.sh docker)"
fi
# From the LAN only SSH and LAN_PORTS answer.
for p in 80 443 2375 8080; do
	case " $lan " in *" $p "*) continue;; esac
	if timeout 4 bash -c "exec 3<>/dev/tcp/$HOST/$p" 2>/dev/null; then fail "tcp $p reachable from the LAN (not in LAN_PORTS)"; else pass "tcp $p closed to the LAN"; fi
done
[ "${crashes:-0}" = 0 ] && pass "no kernel panic records" || warn "$crashes kernel panic record(s) in /data/techo5-linux/crash (*-dmesg-ramoops)"
note "up $((uptime / 3600)) h $((uptime % 3600 / 60)) min"

cat <<EOF

Still to confirm by time or by hand (Stage 9):
  [ ] 24 h healthy:   penguin status, penguin logs supervisor (no restarts)
  [ ] 72 h stable:    uptime > 72 h, no new files in /data/techo5-linux/crash, temp < 75C under load
  [ ] power cut:      unplug, plug back; the unit returns with SSH without help
  [ ] Wi-Fi outage:   router off 1 min; SSH comes back by itself (penguin logs boot)
  [ ] containers:     on the docker kernel, docker run --rm alpine echo ok (pulls a small image)
  [ ] rollback:       docs: README "Way back" (LineageOS boot image: $DONOR_BOOT)
EOF
exit $fails
