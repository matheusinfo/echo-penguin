#!/bin/bash
# build-piper.sh — Piper (offline neural speech) as a self-contained tree for the root filesystem.
#
#   scripts/build-piper.sh
#
# Alpine has Piper only in edge/testing, built against edge's libraries (onnxruntime, ICU, abseil,
# protobuf, a newer libstdc++ and musl), which v3.24's root must not mix with. So nothing of it is
# installed among the root's packages: apk.static installs libpiper and its dependencies from edge into
# a scratch root (no scripts run, so no QEMU), and only piper_exe, the libraries it loads (followed
# through their DT_NEEDED entries) and edge's musl loader are copied out, into /usr/lib/piper. The
# wrapper /usr/local/bin/piper runs piper_exe through that loader with --library-path, so it never
# sees /usr/lib. It reads the root's own espeak-ng data (the same espeak-ng 1.52 as edge's).
#
# Inputs are pinned in config.env (PIPER_*): the piper-tts and libpiper versions (edge moves on: an
# old version leaving the mirror stops this script, and config.env is updated) and the voice, checked
# by SHA-256. Output: $WORK/piper/tree, laid into the root by build-rootfs.sh (about 85 MB: 21 MB of
# program and libraries, 63 MB of voice).
. "$(dirname "$0")/lib.sh"

APK=$HOME/apk/apk.static
[ -x "$APK" ] || die "no $APK: run setup.sh"
command -v readelf >/dev/null || die "readelf (binutils) is needed"
mini=$(ls "$TECHO5"/inputs/alpine-minirootfs-*-armv7.tar.gz 2>/dev/null | head -1)
[ -n "$mini" ] || die "no Alpine minirootfs in $TECHO5/inputs: run setup.sh"

P=$WORK/piper
TREE=$P/tree
say "Piper ($PIPER_TTS, $PIPER_LIB from Alpine edge) into $TREE"
rm -rf "$P/root" "$P/keys" "$P/pkg" "$TREE"
mkdir -p "$P/root" "$P/keys" "$P/pkg" "$P/cache" "$TREE"
tar -xzf "$mini" -C "$P/keys" ./etc/apk/keys

# libpiper and what it needs, from edge, into a scratch root.
"$APK" --root "$P/root" --arch armv7 --initdb --no-scripts --no-cache --keys-dir "$P/keys/etc/apk/keys" \
	-X "$PIPER_REPO/main" -X "$PIPER_REPO/community" -X "$PIPER_REPO/testing" add libpiper >/dev/null 2>&1 || true
"$APK" --root "$P/root" info -v 2>/dev/null | grep -qx "$PIPER_LIB" ||
	die "edge has no $PIPER_LIB any more (it has $("$APK" --root "$P/root" info -v 2>/dev/null | grep '^libpiper-' || echo none)): update PIPER_* in config.env"

# piper_exe comes in piper-tts, whose Python half is not wanted: the package itself, by name.
pkg=$P/cache/$PIPER_TTS.apk
if [ ! -s "$pkg" ] || ! echo "$PIPER_TTS_SHA256  $pkg" | sha256sum -c --quiet 2>/dev/null; then
	curl -fsSL -o "$pkg.tmp" "$PIPER_REPO/testing/armv7/$PIPER_TTS.apk" ||
		die "no $PIPER_TTS in edge/testing any more: update PIPER_* in config.env"
	echo "$PIPER_TTS_SHA256  $pkg.tmp" | sha256sum -c --quiet || die "$PIPER_TTS.apk: wrong SHA-256"
	mv "$pkg.tmp" "$pkg"
fi
tar -xzf "$pkg" -C "$P/pkg" usr/bin/piper_exe usr/share/licenses 2>/dev/null || true
[ -s "$P/pkg/usr/bin/piper_exe" ] || die "no usr/bin/piper_exe in $PIPER_TTS.apk"

# piper_exe and every library it loads, followed through DT_NEEDED, and edge's musl loader.
install -d "$TREE/usr/lib/piper/lib" "$TREE/usr/local/bin" "$TREE/usr/share/piper/voices" "$TREE/usr/share/licenses"
install -m 755 "$P/pkg/usr/bin/piper_exe" "$TREE/usr/lib/piper/piper_exe"
python3 - "$P/root" "$TREE/usr/lib/piper" <<'PY'
import os, shutil, subprocess, sys
root, dest = sys.argv[1:]
def needed(path):
    out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True, check=True).stdout
    return [line.split('[', 1)[1].split(']', 1)[0] for line in out.splitlines() if '(NEEDED)' in line]
todo, seen = [os.path.join(dest, 'piper_exe')], set()
while todo:
    for name in needed(todo.pop()):
        if name in seen:
            continue
        seen.add(name)
        found = [p for p in (os.path.join(root, d, name) for d in ('usr/lib', 'lib')) if os.path.exists(p)]
        if not found:
            sys.exit('build-piper: %s: not in the edge root' % name)
        real = os.path.realpath(found[0])
        shutil.copy(real, os.path.join(dest, 'lib', name))
        os.chmod(os.path.join(dest, 'lib', name), 0o755)
        todo.append(real)
shutil.copy(os.path.realpath(os.path.join(root, 'lib/ld-musl-armhf.so.1')), os.path.join(dest, 'lib/ld-musl-armhf.so.1'))
os.chmod(os.path.join(dest, 'lib/ld-musl-armhf.so.1'), 0o755)
print('   %d libraries' % len(seen))
PY
# Their licenses (GPL-3.0 piper, MIT onnxruntime, Apache-2.0 abseil, ...), next to the root's own.
cp -r "$P/root/usr/share/licenses/." "$P/pkg/usr/share/licenses/." "$TREE/usr/share/licenses/" 2>/dev/null || true
"$APK" --root "$P/root" info -v 2>/dev/null | sort > "$TREE/usr/lib/piper/packages"
echo "$PIPER_TTS" >> "$TREE/usr/lib/piper/packages"

cat > "$TREE/usr/local/bin/piper" <<'SH'
#!/bin/sh
# piper — Piper text to speech: piper_exe with its own libraries (Alpine edge), through their own
# musl loader, and the root's espeak-ng data. Made by echo-penguin's scripts/build-piper.sh; the
# packages it came from are listed in /usr/lib/piper/packages.
#   echo "Bom dia." | piper -m /usr/share/piper/voices/pt_BR-faber-medium.onnx -f out.wav
d=/usr/lib/piper
exec "$d/lib/ld-musl-armhf.so.1" --library-path "$d/lib" "$d/piper_exe" --espeak_data /usr/share/espeak-ng-data "$@"
SH
chmod 755 "$TREE/usr/local/bin/piper"

# The voice, pinned by SHA-256 and cached.
for f in "$PIPER_VOICE_NAME.onnx:$PIPER_VOICE_SHA256" "$PIPER_VOICE_NAME.onnx.json:$PIPER_VOICE_JSON_SHA256"; do
	name=${f%%:*} sum=${f##*:}
	if [ ! -s "$P/cache/$name" ] || ! echo "$sum  $P/cache/$name" | sha256sum -c --quiet 2>/dev/null; then
		curl -fsSL -o "$P/cache/$name.tmp" "$PIPER_VOICE_URL/$name" || die "cannot fetch $PIPER_VOICE_URL/$name"
		echo "$sum  $P/cache/$name.tmp" | sha256sum -c --quiet || die "$name: wrong SHA-256"
		mv "$P/cache/$name.tmp" "$P/cache/$name"
	fi
	install -m 644 "$P/cache/$name" "$TREE/usr/share/piper/voices/$name"
done
rm -rf "$P/root" "$P/keys" "$P/pkg"
say "Piper: $TREE ($(du -sh "$TREE" | cut -f1))"
