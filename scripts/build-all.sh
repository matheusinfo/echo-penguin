#!/bin/bash
# build-all.sh — everything, in order: inputs, both kernels, both boot images, the rootfs.
#
#   scripts/build-all.sh            safe and docker
#   scripts/build-all.sh safe       safe only (no Wi-Fi driver rebuild, no Docker kernel)
#
# Each step stops the run on failure; the kernel steps refuse to finish when the Wi-Fi driver the
# variant will load does not match the kernel (check-modversions.py).
. "$(dirname "$0")/lib.sh"
S=$PENGUIN/scripts
variants=(safe docker)
[ "${1:-}" = safe ] && variants=(safe)

bash "$S/setup.sh"
for v in "${variants[@]}"; do
	bash "$S/build-kernel.sh" "$v"
	bash "$S/build-boot.sh" "$v"
done
bash "$S/build-rootfs.sh"
say "built"
ls -la "$OUT" | sed 's/^/   /'
