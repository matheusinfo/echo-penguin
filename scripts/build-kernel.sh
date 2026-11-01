#!/bin/bash
# build-kernel.sh — build an echo-penguin kernel and prove the Wi-Fi driver will load on it.
#
#   scripts/build-kernel.sh safe|docker
#
#   safe    cronos_defconfig + kernel/safe.config. Symbol CRCs unchanged, so LineageOS's own
#           mt76x8_wlan.ko loads. No Docker (no namespaces).
#   docker  safe + kernel/docker.config (namespaces, cgroups). The vendor module no longer fits,
#           so the MT7668 driver is rebuilt from source (config.env WLAN_*) against this tree.
#
# Same tree, toolchain and release string as TECHO5's build-kernel.sh (KBUILD_BUILD_USER/HOST,
# UTC). Output in $OUT/kernel-<variant>/: Image.gz-dtb, config, Module.symvers and, for docker,
# mt76x8_wlan.ko. The build fails unless check-modversions.py passes for the module the variant
# will actually load: an image that would boot without Wi-Fi is never produced.
. "$(dirname "$0")/lib.sh"

VARIANT=${1:-}
case "$VARIANT" in safe|docker) ;; *) die "usage: build-kernel.sh safe|docker";; esac
[ -x "${CROSS_COMPILE}gcc" ] || die "no toolchain at ${CROSS_COMPILE}gcc: run setup.sh"
at_commit "$KSRC" "$KERNEL_COMMIT" || die "$KSRC is not at $KERNEL_COMMIT: run setup.sh"
[ -z "$(git -C "$KSRC" status --porcelain)" ] || die "$KSRC has local changes (LOCALVERSION would get -dirty)"
# kernel/patches/*.patch: applied for this build and taken out again whatever happens, as TECHO5's
# build-kernel.sh does with PATCHES. A patched tree is a dirty tree, which setlocalversion would mark;
# the vendor modules check the release string, so an empty .scmversion takes the mark off and
# LOCALVERSION pins "-g<commit>" below.
PATCHES=("$PENGUIN"/kernel/patches/*.patch)
[ -e "${PATCHES[0]}" ] || PATCHES=()
if [ ${#PATCHES[@]} -gt 0 ]; then
	trap 'rm -f "$KSRC/.scmversion"; git -C "$KSRC" checkout -- . && note "kernel patches removed"' EXIT
	: > "$KSRC/.scmversion"
	for p in "${PATCHES[@]}"; do
		git -C "$KSRC" apply --check "$p" || die "patch does not apply: $p"
		git -C "$KSRC" apply "$p"
		note "applied $(basename "$p")"
	done
fi

KOUT=$WORK/kout-$VARIANT
DEST=$OUT/kernel-$VARIANT
VENDOR_MODULES=$WORK/lineage/vendor-modules
export ARCH=arm64 CROSS_COMPILE KBUILD_BUILD_USER=techo5 KBUILD_BUILD_HOST=techo5 TZ=UTC
mkdir -p "$KOUT" "$DEST"

say "kernel ($VARIANT)"
fragments=("$PENGUIN/kernel/safe.config")
[ "$VARIANT" = docker ] && fragments+=("$PENGUIN/kernel/docker.config")
make -s -C "$KSRC" O="$KOUT" cronos_defconfig
for f in "${fragments[@]}"; do
	for o in $(fragment_options "$f"); do "$KSRC/scripts/config" --file "$KOUT/.config" --keep-case -e "$o"; done
done
[ ${#PATCHES[@]} -gt 0 ] && "$KSRC/scripts/config" --file "$KOUT/.config" -d LOCALVERSION_AUTO --set-str LOCALVERSION "-g$KERNEL_COMMIT"
make -s -C "$KSRC" O="$KOUT" olddefconfig
for f in "${fragments[@]}"; do
	for o in $(fragment_options "$f"); do
		grep -q "^CONFIG_$o=y" "$KOUT/.config" || die "CONFIG_$o did not survive olddefconfig (a dependency is missing)"
	done
done
make -s -C "$KSRC" O="$KOUT" -j"$(nproc)" Image.gz-dtb modules
release=$(cat "$KOUT/include/config/kernel.release")
[ "$release" = "$KERNEL_RELEASE" ] || die "release is $release, not $KERNEL_RELEASE: the vendor modules would refuse it"
note "release $release"
cp "$KOUT/arch/arm64/boot/Image.gz-dtb" "$KOUT/.config" "$KOUT/Module.symvers" "$DEST/"
mv "$DEST/.config" "$DEST/config"

# The vendor module from the LineageOS zip, for the check below: system.img's /vendor/lib/modules.
if [ ! -e "$VENDOR_MODULES/mt76x8_wlan.ko" ]; then
	zip=${LINEAGE_ZIP:-$(ls "$ROOT"/../echo-show/lineage-18.1-20260904-UNOFFICIAL-cronos.zip 2>/dev/null | head -1)}
	[ -n "$zip" ] && [ -e "$zip" ] || die "need the LineageOS 2026-09-04 cronos zip for the vendor module check (LINEAGE_ZIP=)"
	say "vendor modules from $(basename "$zip")"
	mkdir -p "$WORK/lineage" "$VENDOR_MODULES"
	unzip -o -q "$zip" system.new.dat.br system.transfer.list -d "$WORK/lineage"
	python3 "$PENGUIN/scripts/sdat2img.py" "$WORK/lineage/system.transfer.list" "$WORK/lineage/system.new.dat.br" "$WORK/lineage/system.img"
	rm -f "$WORK/lineage/system.new.dat.br"
	for m in mt76x8_wlan.ko mt76x8_bt.ko; do
		debugfs -R "dump /vendor/lib/modules/$m $VENDOR_MODULES/$m" "$WORK/lineage/system.img" 2>/dev/null
	done
fi

if [ "$VARIANT" = safe ]; then
	say "vendor Wi-Fi module against this kernel"
	python3 "$PENGUIN/scripts/check-modversions.py" "$DEST/Module.symvers" "$VENDOR_MODULES/mt76x8_wlan.ko" ||
		die "the safe kernel changed symbol CRCs: an option in safe.config does not belong there"
else
	say "MT7668 driver ($WLAN_COMMIT) against this kernel"
	at_commit "$WLAN_SRC" "$WLAN_COMMIT" || die "$WLAN_SRC is not at $WLAN_COMMIT: run setup.sh"
	W=$WORK/wlan-$VARIANT
	rm -rf "$W" && mkdir -p "$W"
	cp -a "$WLAN_SRC/module/." "$W/"
	cp "$WLAN_SRC/configs/cronos.config" "$W/.config"
	# The same invocation as the driver's Android.mk in the LineageOS build.
	make -s -C "$KOUT" M="$W" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" MODULE_NAME=mt76x8_wlan -j"$(nproc)" modules
	"${CROSS_COMPILE}strip" --strip-unneeded "$W/mt76x8_wlan.ko"
	python3 "$PENGUIN/scripts/check-modversions.py" "$DEST/Module.symvers" "$W/mt76x8_wlan.ko" ||
		die "the rebuilt Wi-Fi driver does not match this kernel"
	modinfo "$W/mt76x8_wlan.ko" | grep -E '^(vermagic|alias)' | sed 's/^/   /'
	cp "$W/mt76x8_wlan.ko" "$DEST/"
	# For the record: the vendor binary must NOT fit here (otherwise docker.config changed nothing).
	if python3 "$PENGUIN/scripts/check-modversions.py" "$DEST/Module.symvers" "$VENDOR_MODULES/mt76x8_wlan.ko" >/dev/null; then
		note "unexpected: the vendor module still matches this kernel"
	else
		note "vendor module does not fit this kernel (expected); the rebuilt one does"
	fi
fi
sums=(Image.gz-dtb)
[ "$VARIANT" = docker ] && sums+=(mt76x8_wlan.ko)
(cd "$DEST" && sha256sum "${sums[@]}" > SHA256SUMS)
say "kernel $VARIANT: $DEST"
ls -la "$DEST" | sed 's/^/   /'
