#!/bin/bash
# build-boot.sh — the boot image: an echo-penguin kernel with TECHO5's rescue/boot initramfs.
#
#   scripts/build-boot.sh safe|docker [--no-key]
#
# TECHO5's mkimage.py does the packing, as its build-image.sh would: the header, load addresses and
# kernel command line come from this unit's own LineageOS boot image (DONOR_BOOT), the kernel from
# build-kernel.sh, the initramfs from Alpine's minirootfs, TECHO5's rescue apks and init. TECHO5's
# Go helpers (fbprobe and friends) are left out: the initramfs uses them only when present.
#
# docker: the rebuilt mt76x8_wlan.ko goes into the initramfs at /lib/modules/<release>/extra, which
# TECHO5's t5_wifi_up prefers over the vendor tree's module, so rescue keeps its Wi-Fi.
#
# The SSH public key (SSH_PUB, default ~/.ssh/id_ed25519.pub) is built in unless --no-key, so rescue
# accepts it even before the unit has keys on userdata.
# Output: $OUT/echo-penguin-boot-<variant>.img
. "$(dirname "$0")/lib.sh"

VARIANT=${1:-}; shift || true
case "$VARIANT" in safe|docker) ;; *) die "usage: build-boot.sh safe|docker [--no-key]";; esac
NOKEY=
[ "${1:-}" = --no-key ] && NOKEY=1
K=$OUT/kernel-$VARIANT
[ -e "$K/Image.gz-dtb" ] || die "no $K/Image.gz-dtb: run build-kernel.sh $VARIANT"
[ "$VARIANT" = safe ] || [ -e "$K/mt76x8_wlan.ko" ] || die "no $K/mt76x8_wlan.ko: build-kernel.sh docker did not finish"
[ -e "$DONOR_BOOT" ] || die "no donor boot image at $DONOR_BOOT (setup.sh says where it comes from)"
python3 -c 'import fdt' 2>/dev/null || true   # only patch-dtb.py needs it; mkimage.py does not
I=$TECHO5/inputs
mini=$(ls "$I"/alpine-minirootfs-*-armv7.tar.gz | head -1)

apk_file() { # TECHO5's build-image.sh: the listed file, or the version fetch-inputs.py took instead
	local name=${2%-*-r*.apk} have
	[ -f "$1/$2" ] && { echo "$1/$2"; return; }
	have=$(ls "$1/$name"-[0-9]*-r[0-9]*.apk 2>/dev/null | sort -V | tail -1)
	echo "${have:-$1/$2}"
}
apks=()
for a in $(sed 's/#.*//' "$TECHO5/tools/linux/packages.txt"); do
	case "$a" in
	busybox-static-*) continue;;
	wpa_supplicant-2.9*|libssl1.1*|libcrypto1.1*|libnl3-3.5*) apks+=(--apk "$(apk_file "$I/apks312" "$a")");;
	*) apks+=(--apk "$(apk_file "$I/apks" "$a")");;
	esac
done

extra=()
if [ "$VARIANT" = docker ]; then
	extra+=(--copy "$K/mt76x8_wlan.ko=/lib/modules/$KERNEL_RELEASE/extra/mt76x8_wlan.ko")
fi
if [ -z "$NOKEY" ]; then
	[ -e "$SSH_PUB" ] || die "no SSH public key at $SSH_PUB (SSH_PUB=..., or --no-key)"
	extra+=(--copy "$SSH_PUB=/root/.ssh/authorized_keys")
fi

LIB=$WORK/techo5-lib.sh
techo5_lib "$LIB"
IMG=$OUT/echo-penguin-boot-$VARIANT.img
say "boot image ($VARIANT$([ -n "$NOKEY" ] && echo ', no key'))"
python3 "$TECHO5/tools/linux/mkimage.py" --kernel-image "$DONOR_BOOT" --kernel "$K/Image.gz-dtb" \
	--rootfs "$mini" "${apks[@]}" \
	--init "$TECHO5/tools/linux/init" \
	--add "$I/busybox.static=/bin/busybox.static" \
	--script "$TECHO5/tools/linux/slotctl=/usr/local/sbin/slotctl" \
	--script "$TECHO5/tools/linux/bootctl=/usr/local/sbin/bootctl" \
	--script "$LIB=/lib/techo5-lib.sh" \
	--script "$TECHO5/tools/linux/rescue-profile.sh=/etc/profile.d/rescue.sh" \
	"${extra[@]}" \
	--compress xz --cmdline-append "techo5=linux${SCREEN_CMDLINE:+ $SCREEN_CMDLINE}" -o "$IMG"
size=$(stat -c %s "$IMG")
[ "$size" -le $((16 * 1024 * 1024)) ] || die "$IMG is $size bytes; the boot partition (p9) is 16 MiB"
(cd "$OUT" && sha256sum "$(basename "$IMG")" > "$(basename "$IMG").sha256")
say "boot image: $IMG ($((size / 1024)) KiB of 16384)"
