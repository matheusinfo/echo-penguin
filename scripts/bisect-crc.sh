#!/bin/bash
# bisect-crc.sh — which kernel options change the symbol CRCs the vendor modules were built against.
#
#   bisect-crc.sh OPTION[+OPTION...] ...   each argument alone on top of cronos_defconfig (A+B: together)
#
# Builds only the objects that export the symbols the vendor Wi-Fi/BT modules import most (module_layout,
# netdev, skb, sdio, kthread, slab, seq_file, cfg80211), reads their __crc_* symbols and compares them
# with the same objects built from the plain defconfig. Seconds per option instead of a full kernel.
# Environment: KSRC, CROSS_COMPILE, WORK (where the kout-crc-* directories go).
set -euo pipefail
export LC_ALL=C
KSRC=${KSRC:?}
WORK=${WORK:?}
export ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE:?}
OBJS="kernel/module.o net/core/dev.o net/core/skbuff.o kernel/kthread.o mm/slab_common.o fs/seq_file.o
drivers/mmc/core/sdio_io.o drivers/mmc/core/sdio_irq.o net/wireless/mlme.o net/wireless/core.o fs/proc/generic.o
kernel/locking/mutex.o kernel/sched/core.o fs/open.o fs/read_write.o fs/char_dev.o drivers/base/core.o mm/vmalloc.o kernel/time/timer.o"

crcs() { # dir -> "sym crc" lines
	for o in $OBJS; do
		[ -e "$1/$o" ] && ${CROSS_COMPILE}nm "$1/$o" | awk '$3 ~ /^__crc_/ {sub("__crc_","",$3); print $3, $1}'
	done | sort
}
build() { # dir option-or-empty
	local d=$1 opt=$2
	mkdir -p "$d"
	make -s -C "$KSRC" O="$d" cronos_defconfig >/dev/null
	for o in ${opt//+/ }; do "$KSRC/scripts/config" --file "$d/.config" -e "$o"; done
	make -s -C "$KSRC" O="$d" olddefconfig >/dev/null
	make -s -C "$KSRC" O="$d" prepare >/dev/null 2>&1
	make -s -C "$KSRC" O="$d" -j4 $OBJS >/dev/null 2>&1 || true
	crcs "$d" > "$d/crcs.txt"
}
[ -s "$WORK/kout-crc-base/crcs.txt" ] || build "$WORK/kout-crc-base" ""
for opt in "$@"; do
	(
		d=$WORK/kout-crc-$opt
		build "$d" "$opt"
		n=$(join "$WORK/kout-crc-base/crcs.txt" "$d/crcs.txt" | awk '$2 != $3' | wc -l)
		stuck=yes; for o in ${opt//+/ }; do grep -q "^CONFIG_$o=y" "$d/.config" || stuck="no: $o"; done
		echo "$opt: $n of $(wc -l < "$d/crcs.txt") CRCs differ$([ "$stuck" = yes ] || echo " (did not stick, $stuck)")$(join "$WORK/kout-crc-base/crcs.txt" "$d/crcs.txt" | awk '$2 != $3 {printf " %s", $1}' | cut -c1-120)"
	) &
	while [ "$(jobs -r | wc -l)" -ge 4 ]; do sleep 1; done
done
wait
