#!/bin/sh
# mkrootfs.sh — build the echo-penguin root filesystem tarball. A trimmed fork of TECHO5's
# tools/linux/mkrootfs.sh: same base, same apk use (packages installed properly, with their scripts,
# under QEMU on an x86 host), same state-on-userdata symlinks, so TECHO5's slotctl, initramfs and
# installer take it as one of their own. Driven by build-rootfs.sh, which stages <indir>.
#
#   mkrootfs.sh -i <indir> -o <out.tar.gz> -w <workdir> -V <version> [-z <timezone>] [-A <apk>]
#
# <indir>:
#   inputs/alpine-minirootfs-*-armv7.tar.gz   the base (one only)
#   inputs/apks312/*.apk                      wpa_supplicant 2.9 + libssl1.1/libcrypto1.1/libnl3 (TECHO5)
#   packages.txt                              rootfs-packages.txt
#   tools/slotctl tools/bootctl tools/techo5-lib.sh   from TECHO5
#   overlay-techo5/                           TECHO5's tools/linux/rootfs
#   overlay/                                  rootfs/ (laid over TECHO5's)
#   modules/docker/mt76x8_wlan.ko             optional: the Wi-Fi driver rebuilt for the docker kernel
#   licenses/                                 optional: license texts, copied to /usr/share/licenses
set -e

IN=; OUT=; WORK=; VERSION=dev; TZNAME=UTC; APK=apk
while [ $# -gt 0 ]; do
	case "$1" in
	-i) IN=$2; shift 2;;
	-o) OUT=$2; shift 2;;
	-w) WORK=$2; shift 2;;
	-V) VERSION=$2; shift 2;;
	-z) TZNAME=$2; shift 2;;
	-A) APK=$2; shift 2;;
	*) echo "mkrootfs: unknown argument $1" >&2; exit 1;;
	esac
done
[ -n "$IN" ] && [ -n "$OUT" ] && [ -n "$WORK" ] || { echo "usage: mkrootfs.sh -i indir -o out.tar.gz -w workdir [-V version]" >&2; exit 1; }
say() { echo "mkrootfs: $*"; }
R=$WORK/root
rm -rf "$R"
mkdir -p "$R"

mini=$(ls "$IN"/inputs/alpine-minirootfs-*-armv7.tar.gz)
[ "$(echo "$mini" | wc -l)" -eq 1 ] || { echo "mkrootfs: need exactly one alpine-minirootfs-*-armv7.tar.gz" >&2; exit 1; }
say "base: $(basename "$mini")"
# In a user namespace that maps only root (no newuidmap on the host), the few files the base owns
# by another id (/etc/shadow, group shadow) cannot keep it: they become root's, which is harmless here.
if ! tar -xzf "$mini" -C "$R" 2>/dev/null; then
	say "ownership other than root not kept (user namespace maps only root)"
	tar --no-same-owner -xzf "$mini" -C "$R"
fi
cp /etc/resolv.conf "$R/etc/resolv.conf"

pkgs=$(sed 's/#.*//' "$IN/packages.txt" | tr '\n' ' ')
say "apk add: $pkgs"
$APK --root "$R" --arch armv7 --no-cache add $pkgs
say "apk add (local, wpa_supplicant 2.9): $(ls "$IN"/inputs/apks312/*.apk | xargs -n1 basename | tr '\n' ' ')"
# Signed by Alpine's -524d27bb key, which the minirootfs carries (see TECHO5's mkrootfs.sh).
$APK --root "$R" --arch armv7 --no-cache add "$IN"/inputs/apks312/*.apk
$APK --root "$R" --arch armv7 info -v | sort > "$R/etc/penguin-packages"

# These Android kernels (CONFIG_ANDROID_PARANOID_NETWORK) give a socket only to root or a member of
# inet (3003): the group exists, so a service later run as another user can be added to it.
grep -q '^inet:' "$R/etc/group" || echo 'inet:x:3003:' >> "$R/etc/group"

# Vendor tree: never in the image; the unit's own is kept in the store and bound at /vendor.
install -d "$R/vendor"

# TECHO5's tools (slot store, A/B record, shared shell library), then the two overlays.
# /lib/modules is a mount point: on the docker kernel boot.sh binds the rebuilt Wi-Fi driver over it
# (p_wifi_module), and the minirootfs has no such directory to mount on.
install -d "$R/usr/local/bin" "$R/usr/local/sbin" "$R/lib" "$R/lib/modules" "$R/usr/lib/penguin/modules/docker"
install -m 755 "$IN/tools/slotctl" "$R/usr/local/sbin/slotctl"
install -m 755 "$IN/tools/bootctl" "$R/usr/local/sbin/bootctl"
install -m 644 "$IN/tools/techo5-lib.sh" "$R/lib/techo5-lib.sh"
say "overlays: TECHO5's, then echo-penguin's"
# Owned by root and not group/world-writable, whatever the build machine's user and umask: a plain
# tar carried the builder's uid (1000) and 775/664 modes onto /, /etc, /usr/local/sbin (v0.1.1).
# (busybox tar has no --owner/--mode, so the owner and modes are fixed after the copy.)
for o in "$IN/overlay-techo5" "$IN/overlay"; do
	(cd "$o" && tar -cf - .) | tar -xf - -C "$R"
	(cd "$o" && find . ! -type l) | while read -r p; do
		chown 0:0 "$R/$p" && chmod go-w "$R/$p"
	done
done
find "$R/etc/techo5" "$R/etc/penguin" "$R/usr/local/sbin" "$R/usr/local/bin" "$R/lib/techo5-lib.sh" "$R/lib/penguin.sh" \
	"$R/etc/inittab" "$R/etc/profile.d" "$R/etc/hostname" "$R/etc/motd" -type f -exec sed -i 's/\r$//' {} +
chmod 755 "$R"/etc/techo5/*.sh "$R"/usr/local/sbin/* "$R"/usr/local/bin/*
# TECHO5's overlay brings scripts for features this image does not have; they stay harmless, but
# the AirPlay/voice firewall chains are replaced by echo-penguin's techo5-firewall above.

if [ -e "$IN/modules/docker/mt76x8_wlan.ko" ]; then
	install -m 644 "$IN/modules/docker/mt76x8_wlan.ko" "$R/usr/lib/penguin/modules/docker/mt76x8_wlan.ko"
	say "Wi-Fi driver for the docker kernel included"
else
	say "no Wi-Fi driver for the docker kernel: this rootfs is for the safe kernel only"
fi
if [ -d "$IN/licenses" ]; then
	mkdir -p "$R/usr/share/licenses"
	cp -r "$IN/licenses/." "$R/usr/share/licenses/"
	find "$R/usr/share/licenses" -type f -exec chmod 644 {} +
fi

# State that must survive an image change lives on userdata (TECHO5's layout).
rm -rf "$R/etc/dropbear"
ln -s /data/techo5-linux/dropbear "$R/etc/dropbear"
rm -f "$R/etc/resolv.conf"
ln -s /run/resolv.conf "$R/etc/resolv.conf"
rm -f "$R/etc/hosts"
ln -s /run/hosts "$R/etc/hosts"
# Root: no password, no key in the image. Keys live on userdata (the installer's --ssh-key).
rm -rf "$R/root/.ssh"
ln -s /data/misc/techo5/ssh "$R/root/.ssh"
sed -i 's|^root:[^:]*:|root:*:|' "$R/etc/shadow"
# Docker's own state paths, on userdata or tmpfs (daemon.json says the same; these catch anything
# that ignores it, such as the CLI's config).
rm -rf "$R/var/lib/docker" "$R/root/.docker"
ln -s /data/docker "$R/var/lib/docker"

[ -e "$R/usr/share/zoneinfo/$TZNAME" ] || { say "warning: no zoneinfo for $TZNAME; UTC"; TZNAME=UTC; }
echo "$TZNAME" > "$R/etc/techo5/default-timezone"
rm -f "$R/etc/localtime" "$R/etc/timezone"
ln -s /data/misc/techo5/localtime "$R/etc/localtime"
ln -s /data/misc/techo5/timezone "$R/etc/timezone"

mkdir -p "$R/store" "$R/data" "$R/run" "$R/proc" "$R/sys" "$R/dev" "$R/tmp" "$R/newroot"
chmod 1777 "$R/tmp"
echo "echo-penguin rootfs $VERSION built $(date -u '+%Y-%m-%dT%H:%MZ'), techo5 $(cat "$IN/techo5-commit" 2>/dev/null)" > "$R/etc/techo5-release"

# What slotctl insists on (sbin/init, usr/local/bin/techo5, etc/techo5/boot.sh, etc/inittab).
for f in sbin/init usr/local/bin/techo5 usr/local/bin/penguin-ui usr/local/sbin/penguin-sound etc/techo5/boot.sh etc/inittab usr/sbin/xtables-legacy-multi usr/bin/dockerd usr/bin/python3 usr/bin/aplay usr/bin/amixer lib/modules; do
	[ -e "$R/$f" ] || [ -L "$R/$f" ] || { echo "mkrootfs: $f missing from the root" >&2; exit 1; }
done

# Python's parts a read-only appliance never uses: pip's bootstrap wheels, the pydoc topic index,
# turtle demos, the static library for building extensions.
rm -rf "$R"/usr/lib/python3*/ensurepip "$R"/usr/lib/python3*/pydoc_data "$R"/usr/lib/python3*/turtledemo \
	"$R"/usr/lib/python3*/config-3*
say "packing"
rm -f "$OUT"
# Guard: nothing owned by a build-machine user (uid/gid >= 1000; 65534 is Alpine's nobody) and nothing
# world-writable but sticky dirs (busybox find has no -uid, hence stat).
own=$(find "$R" -xdev ! -type l -exec stat -c '%u %g %n' {} + | awk '($1>=1000&&$1!=65534)||($2>=1000&&$2!=65534)' | head -5) &&
	ww=$(find "$R" -xdev ! -type l -perm -0002 ! -perm -1000 -print | head -5) || { echo "rootfs ownership check failed to run" >&2; exit 1; }
[ -z "$own$ww" ] || { printf 'rootfs has build-machine owners or world-writable files:\n%s\n%s\n' "$own" "$ww" >&2; exit 1; }
tar -czf "$OUT" -C "$R" .
say "$(cat "$R/etc/techo5-release")"
say "$OUT: $(du -h "$OUT" | cut -f1) ($(du -sh "$R" | cut -f1) unpacked)"
