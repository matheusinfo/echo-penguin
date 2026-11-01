# lib.sh — shared by scripts/: paths, pinned versions, small helpers. Sourced, not run.
set -euo pipefail
export LC_ALL=C

# The repository root: config.env, kernel/, rootfs/, scripts/.
PENGUIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$PENGUIN
# shellcheck source=../config.env
. "$PENGUIN/config.env"
case "$PENGUIN_BUILD" in /*) ;; *) PENGUIN_BUILD=$ROOT/$PENGUIN_BUILD;; esac
case "$WORK" in /*) ;; *) WORK=$ROOT/$WORK;; esac
case "$OUT" in /*) ;; *) OUT=$ROOT/$OUT;; esac
mkdir -p "$PENGUIN_BUILD"
PENGUIN_BUILD=$(cd "$PENGUIN_BUILD" && pwd)
WORK=$(realpath -m "$WORK")
OUT=$(realpath -m "$OUT")
TECHO5=${TECHO5:-$PENGUIN_BUILD/techo5}
KSRC=$WORK/kernel
WLAN_SRC=$WORK/wlan-src
CROSS_COMPILE=${CROSS_COMPILE:-$WORK/toolchain/$TOOLCHAIN_DIR/bin/aarch64-linux-gnu-}
DONOR_BOOT=${DONOR_BOOT:-$TECHO5/inputs/boot-lineage-18.1-20260904-cronos.img}
# The key the unit accepts: SSH_PUB, else the one made for TECHO5 on this machine, else the usual one.
if [ -z "${SSH_PUB:-}" ]; then
	for SSH_PUB in "$HOME/.ssh/techo5.pub" "$HOME/.ssh/id_ed25519.pub"; do [ -e "$SSH_PUB" ] && break; done
fi
SSH_KEY=${SSH_KEY:-${SSH_PUB%.pub}}
mkdir -p "$WORK" "$OUT"

say() { printf '== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# at_commit <dir> <commit>: whether a git checkout is at that commit (short or full).
at_commit() {
	local head
	head=$(git -C "$1" rev-parse HEAD 2>/dev/null) || return 1
	case "$head" in "$2"*) return 0;; *) return 1;; esac
}

# fragment_options <file>: the option names (no CONFIG_, no =y) a kernel fragment turns on.
fragment_options() {
	sed -n 's/#.*//;s/^CONFIG_\([A-Za-z0-9_]*\)=y[[:space:]]*$/\1/p' "$1"
}

# fragment_disabled <file>: the option names a kernel fragment turns off (CONFIG_X=n lines).
fragment_disabled() {
	sed -n 's/#.*//;s/^CONFIG_\([A-Za-z0-9_]*\)=n[[:space:]]*$/\1/p' "$1"
}

# techo5_lib <out>: TECHO5's tools/linux/techo5-lib.sh with echo-penguin's fixes, written to <out>.
# The checkout is never edited; each fix must apply, so a change upstream stops the build here.
#  1. t5_ntp: `: > /run/techo5/ntp-set 2>/dev/null`. A failed redirection on a special builtin (`:`)
#     makes a POSIX shell exit, whatever 2>/dev/null says; in the rescue initramfs /run/techo5 does not
#     exist, so the moment NTP set the clock, PID 1 exited and the kernel panicked (seen on the unit:
#     "/init: line 569: can't create /run/techo5/ntp-set", then "Attempted to kill init").
techo5_lib() {
	local src=$TECHO5/tools/linux/techo5-lib.sh
	local bad=': > /run/techo5/ntp-set 2>/dev/null'
	local good='mkdir -p /run/techo5 2>/dev/null; touch /run/techo5/ntp-set 2>/dev/null'
	grep -qF "$bad" "$src" || die "techo5-lib.sh changed upstream: the ntp-set fix no longer applies; check t5_ntp"
	awk -v bad="$bad" -v good="$good" '{ i = index($0, bad); if (i) $0 = substr($0, 1, i - 1) good substr($0, i + length(bad)); print }' "$src" > "$1"
	grep -qF "$good" "$1" && ! grep -qF "$bad" "$1" || die "the ntp-set fix did not apply"
}

