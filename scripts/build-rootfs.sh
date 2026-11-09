#!/bin/bash
# build-rootfs.sh — stage the inputs and build the echo-penguin root filesystem tarball.
#
#   scripts/build-rootfs.sh [-V version] [-z timezone]
#
# Runs scripts/mkrootfs.sh the way TECHO5's wsl-build.sh runs its own: Alpine's static apk installs
# the armv7 packages, QEMU user emulation runs their install scripts, and a user namespace owns the
# files as root without sudo. Needs the qemu-arm binfmt handler (README: "Build host").
#
# Includes the Wi-Fi driver for the docker kernel when $OUT/kernel-docker/mt76x8_wlan.ko exists
# (build-kernel.sh docker); without it the rootfs only suits the safe kernel, and says so.
# Includes Piper, the alarm's natural voice, from $WORK/piper/tree (build-piper.sh, run here the first
# time); PIPER=0 leaves it out, and a failed Piper build only leaves the alarm with espeak-ng.
# Output: $OUT/echo-penguin-rootfs-<version>.tar.gz
. "$(dirname "$0")/lib.sh"

VERSION=v$(date -u +%Y.%m.%d)-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)
TZNAME=America/Sao_Paulo
while [ $# -gt 0 ]; do
	case "$1" in
	-V) VERSION=$2; shift 2;;
	-z) TZNAME=$2; shift 2;;
	*) die "unknown argument $1";;
	esac
done

APK=$HOME/apk/apk.static
[ -x "$APK" ] || die "no $APK: run setup.sh"
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] ||
	die "no qemu-arm binfmt handler: apk must run armv7 install scripts (README, \"Build host\")"
[ -e "$TECHO5/tools/linux/slotctl" ] || die "no TECHO5 checkout at $TECHO5: run setup.sh"

STAGE=$WORK/rootfs-stage
say "staging in $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/inputs" "$STAGE/tools" "$STAGE/modules/docker"
cp "$TECHO5"/inputs/alpine-minirootfs-*-armv7.tar.gz "$STAGE/inputs/"
cp -r "$TECHO5/inputs/apks312" "$STAGE/inputs/"
cp "$TECHO5/tools/linux/slotctl" "$TECHO5/tools/linux/bootctl" "$STAGE/tools/"
techo5_lib "$STAGE/tools/techo5-lib.sh"
cp -r "$TECHO5/tools/linux/rootfs" "$STAGE/overlay-techo5"
cp -r "$PENGUIN/rootfs" "$STAGE/overlay"
# Piper, the alarm's natural voice (build-piper.sh; PIPER=0 leaves it out): built once, then reused.
if [ "${PIPER:-1}" = 1 ] && [ ! -x "$WORK/piper/tree/usr/lib/piper/piper_exe" ]; then
	"$PENGUIN/scripts/build-piper.sh" || note "Piper could not be built: the alarm speaks with espeak-ng only"
fi
if [ "${PIPER:-1}" = 1 ] && [ -x "$WORK/piper/tree/usr/lib/piper/piper_exe" ]; then
	cp -a "$WORK/piper/tree/." "$STAGE/overlay/"
	note "Piper: included ($(tail -1 "$WORK/piper/tree/usr/lib/piper/packages"), voice $(ls "$WORK/piper/tree/usr/share/piper/voices" | grep '\.onnx$' | tr '\n' ' '))"
else
	note "no Piper: the alarm speaks with espeak-ng only"
fi
cp "$PENGUIN/rootfs-packages.txt" "$STAGE/packages.txt"
cp "$PENGUIN/scripts/mkrootfs.sh" "$STAGE/mkrootfs.sh"
git -C "$TECHO5" rev-parse --short=8 HEAD > "$STAGE/techo5-commit"
if [ -e "$OUT/kernel-docker/mt76x8_wlan.ko" ]; then
	cp "$OUT/kernel-docker/mt76x8_wlan.ko" "$STAGE/modules/docker/"
	note "Wi-Fi driver for the docker kernel: included"
else
	note "no $OUT/kernel-docker/mt76x8_wlan.ko: this rootfs suits the safe kernel only"
fi

say "mkrootfs (armv7, under QEMU)"
TARBALL=$OUT/echo-penguin-rootfs-$VERSION.tar.gz
BUILD=$WORK/rootfs-build
rm -f "$TARBALL"
# File ownership: apk sets owners other than root on some package files. A user namespace keeps them
# only with the whole subuid range mapped (newuidmap, from the uidmap package); without it a
# throwaway Alpine container does the build as real root (binfmt reaches into containers); the
# root-only namespace is the last resort and fails on such files.
if command -v newuidmap >/dev/null; then
	unshare -Ur --map-auto sh "$STAGE/mkrootfs.sh" -i "$STAGE" -o "$TARBALL" -w "$BUILD" -V "$VERSION" -z "$TZNAME" -A "$APK"
elif docker info >/dev/null 2>&1; then
	note "no newuidmap: building as root in an alpine:3.24 container"
	docker run --rm -v "$STAGE:/in:ro" -v "$APK:/apk.static:ro" -v "$WORK:/work" -v "$OUT:/out" alpine:3.24 sh -c '
		sh /in/mkrootfs.sh -i /in -o "/out/$1" -w /work/rootfs-build -V "$2" -z "$3" -A /apk.static; r=$?
		chown -R "$4" /work/rootfs-build "/out/$1" 2>/dev/null; exit $r' sh \
		"$(basename "$TARBALL")" "$VERSION" "$TZNAME" "$(id -u):$(id -g)"
else
	note "no newuidmap and no Docker: files apk gives to other users will make the build fail"
	unshare -Ur sh "$STAGE/mkrootfs.sh" -i "$STAGE" -o "$TARBALL" -w "$BUILD" -V "$VERSION" -z "$TZNAME" -A "$APK"
fi
[ -s "$TARBALL" ] || die "no $TARBALL"
(cd "$OUT" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256")
say "rootfs: $TARBALL"
