#!/bin/sh
# echo-penguin: shutdown (see /etc/inittab). The supervisor first, then dockerd (which stops the
# containers), then everything else.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
stop() { # name seconds
	pid=$(pidof "$1") || return 0
	kill -TERM $pid 2>/dev/null
	n=0; while [ $n -lt "$2" ] && pidof "$1" >/dev/null; do sleep 1; n=$((n+1)); done
}
stop techo5 40
stop dockerd 20
stop containerd 10
killall dropbear ntpd udhcpc wpa_supplicant 2>/dev/null
# The watchdog must be told to stop, or it resets the unit mid-shutdown; the reboot itself is quick.
killall -TERM watchdog 2>/dev/null
cp /run/boot.log /data/techo5-linux/boot.log 2>/dev/null
swapoff -a 2>/dev/null
sync
umount -a -r 2>/dev/null
sync
