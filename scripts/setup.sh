#!/bin/bash
# setup.sh — fetch everything the builds need, at the commits pinned in config.env. Safe to re-run:
# what is already there and at the right commit is left alone.
#
#   scripts/setup.sh
#
# Everything goes into PENGUIN_BUILD (config.env; default ../echo-penguin-build), not this repository.
# Fetches: TECHO5, the LineageOS kernel tree, the MT7668 Wi-Fi driver source, Arm's
# GCC 8.3 and TECHO5's public inputs (Alpine base, busybox.static, apk.static, rescue apks). Copies this unit's LineageOS boot image
# (the donor for the boot image header and command line) from the earlier TECHO5 backup when found.
# Needs no root.
. "$(dirname "$0")/lib.sh"

clone_at() { # url dir commit [branch]
	local url=$1 dir=$2 commit=$3 branch=${4:-}
	if [ ! -d "$dir/.git" ]; then
		say "clone $url"
		git clone -q --filter=blob:none ${branch:+--single-branch -b "$branch"} "$url" "$dir"
	fi
	if ! at_commit "$dir" "$commit"; then
		git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$dir" fetch -q origin ${branch:+"$branch"}
		git -C "$dir" checkout -q "$commit"
	fi
	note "$(basename "$dir") at $(git -C "$dir" rev-parse --short=12 HEAD)"
}

clone_at "$TECHO5_URL" "$TECHO5" "$TECHO5_COMMIT"
clone_at "$KERNEL_URL" "$KSRC" "$KERNEL_COMMIT" "$KERNEL_BRANCH"
clone_at "$WLAN_URL" "$WLAN_SRC" "$WLAN_COMMIT"
[ -z "$(git -C "$KSRC" status --porcelain)" ] || die "$KSRC has local changes: the release string would get -dirty"

if [ ! -x "${CROSS_COMPILE}gcc" ]; then
	say "toolchain"
	mkdir -p "$WORK/toolchain"
	curl -fL# "$TOOLCHAIN_URL" | tar -xJ -C "$WORK/toolchain"
fi
note "$("${CROSS_COMPILE}gcc" --version | head -1)"

if [ ! -e "$TECHO5/inputs/apk.static" ] || ! ls "$TECHO5"/inputs/alpine-minirootfs-*-armv7.tar.gz >/dev/null 2>&1; then
	say "TECHO5 inputs"
	python3 "$TECHO5/tools/fetch-inputs.py" --device show
fi
mkdir -p "$HOME/apk"
[ -x "$HOME/apk/apk.static" ] || install -m 755 "$TECHO5/inputs/apk.static" "$HOME/apk/apk.static"

# The donor boot image: this unit's own LineageOS boot partition (header, load addresses, kernel
# command line). Never published, never fetched: TECHO5's installer saved one in its backups.
if [ ! -e "$DONOR_BOOT" ]; then
	for f in "$TECHO5"/backups/*/boot-lineage.img "$ROOT"/../echo-show/techo5/backups/*/boot-lineage.img; do
		[ -e "$f" ] || continue
		cp "$f" "$DONOR_BOOT"
		note "donor boot image from $f"
		break
	done
fi
[ -e "$DONOR_BOOT" ] && note "donor: $DONOR_BOOT ($(sha256sum "$DONOR_BOOT" | cut -c1-16))" ||
	note "no donor boot image yet: with LineageOS running, adb pull /dev/block/mmcblk0p9 $DONOR_BOOT"
[ -e "$SSH_PUB" ] && note "SSH key: $SSH_PUB" || note "no SSH public key at $SSH_PUB (set SSH_PUB=)"
say "setup done"
