# echo-penguin

Headless Alpine Linux for the Amazon Echo Show 5 2nd gen (`cronos`), built on top of the
[TECHO5](https://github.com/HuskerMinion/techo5) boot chain (used as is, at the commit pinned in
[config.env](config.env)): no Android, Wi-Fi, key-only SSH, Docker when the kernel allows it, and
24/7 operation. What runs on top (containers, services) is outside the scope of this project.

> **Warning.** Installing erases LineageOS from the unit. It needs an Echo Show 5 2nd gen that is
> already unlocked and running LineageOS 18.1 (see [References](#references)). You do this at your
> own risk.

Key design decisions:

- **Docker and the vendor Wi-Fi do not coexist in the same kernel.** The options Docker requires
  (`NAMESPACES`, `CPUSETS`, `CGROUP_DEVICE`, `CGROUP_PIDS`, `BLK_CGROUP`, `POSIX_MQUEUE`) change the CRCs
  of symbols that the binary `mt76x8_wlan.ko` imports, and the kernel rejects the module. That is why there are **two
  kernels**:
  - **safe**: `cronos_defconfig` + only options that do not touch the CRCs. The LineageOS Wi-Fi loads;
    no Docker. This is the recommended one for the first install.
  - **docker**: adds what Docker needs ([kernel/docker.config](kernel/docker.config)). The MT7668 driver is **rebuilt from source** (the same source
    LineageOS uses) against this kernel; the build only finishes if the CRCs match.
- **busybox init, not OpenRC**, and **Alpine 3.24, not 3.20**: this is what TECHO5 uses today; changing it
  would break its initramfs, `slotctl` and installer.
- The supervisor is named `/usr/local/bin/techo5` because TECHO5's `slotctl`, slot test and installer
  look for a process with that name.

## Structure

```
config.env               pinned versions and commits (TECHO5, kernel, Wi-Fi driver, toolchain)
kernel/safe.config       options added to cronos_defconfig in both kernels (CRC-neutral, measured)
kernel/docker.config     docker kernel options (change CRCs: require the rebuilt driver)
rootfs-packages.txt      Alpine packages in the rootfs
rootfs/                  overlay on top of TECHO5's (boot.sh, supervisor, firewall, penguin command...)
scripts/                 build and operation from the PC (below)
```

This repository contains only the project. Everything downloaded or generated lives **outside** it, in
`../echo-penguin-build/` (change with `PENGUIN_BUILD=`, see [config.env](config.env)):

```
../echo-penguin-build/
  techo5/                  TECHO5 at the pinned commit (setup.sh clones it) and its inputs
  work/                    kernel, toolchain, Wi-Fi driver, extracted LineageOS
  work/out/                finished images (boot, rootfs) and kernels
```

## Build machine

Linux x86_64 with `git`, `python3` (+ `brotli`), `make`, `gcc`, `bc`, `curl`, `debugfs` (e2fsprogs),
`unshare`, and Docker (the rootfs is generated as root in a container when the PC does not have `newuidmap`, from
the `uidmap` package). Root is not needed, with one exception:

**QEMU binfmt for armv7.** `apk` runs the package install scripts inside the armv7
rootfs, as in TECHO5. One of the two, once per PC boot:

```bash
sudo apt install qemu-user-static binfmt-support            # permanent
# or, without apt (lasts until the PC reboots):
docker run --privileged --rm tonistiigi/binfmt:qemu-v9.2.2 --install arm
```

You also need:

- the LineageOS 2026-09-04 zip (`lineage-18.1-20260904-UNOFFICIAL-cronos.zip`, see
  [References](#references)), to extract the `mt76x8_wlan.ko` used in the CRC check. Point
  `LINEAGE_ZIP=` at it (default: `../echo-show/`, next to this checkout);
- the LineageOS boot image of **your unit** (donor of the header and command line): `setup.sh`
  copies it from the backup the TECHO5 installer made in `techo5/backups/<serial>/boot-lineage.img`
  (`TECHO5_BACKUPS=` to point elsewhere), or tells you how to `adb pull` it.

Scripts that talk to the unit's USB console (`console.py`, `console-push.py`, `finish-install.sh`)
need its serial number: `--serial <serial>` or `ECHO_SERIAL=<serial>`.

## Build

```bash
scripts/build-all.sh          # setup + safe and docker kernels + boot images + rootfs
# or step by step:
scripts/setup.sh              # downloads everything at the pinned commits
scripts/build-kernel.sh safe  # kernel + check of the LineageOS mt76x8_wlan.ko
scripts/build-kernel.sh docker  # kernel + rebuilt driver + check
scripts/build-boot.sh safe    # ../echo-penguin-build/work/out/echo-penguin-boot-safe.img
scripts/build-boot.sh docker  # ../echo-penguin-build/work/out/echo-penguin-boot-docker.img
scripts/build-rootfs.sh       # ../echo-penguin-build/work/out/echo-penguin-rootfs-<version>.tar.gz
```

The SSH key embedded and pushed is `~/.ssh/techo5.pub` (or `SSH_PUB=...`). Diagnostic tools:
`check-modversions.py <Module.symvers> <module.ko>` and `bisect-crc.sh OPTION[+OPTION]...`.

## Installation (first time, unit running LineageOS)

With the Echo on LineageOS, USB debugging and "Rooted debugging" enabled, USB cable connected:

```bash
scripts/install.sh safe --dry-run     # checks everything, writes nothing
scripts/install.sh safe               # asks before erasing system (p12)
```

This is TECHO5's `tools/install-show.py` with our images: backup of the LineageOS boot, push of the
rootfs, `fastboot flash boot`, slot store on `mmcblk0p12` (**erases LineageOS**), the unit's own
vendor tree, slot a, SSH key, and it follows the first boot. The Wi-Fi is whatever LineageOS had saved
(or `--wifi <network>`).

If the installation stops at the slot store (the unit stays in rescue, with a console on `/dev/ttyACM*`):
`scripts/finish-install.sh` finishes it over the USB console. `scripts/console.py 'command'` runs a command
on the console when the unit has no network.

## Verify

```bash
HOST=<echo-ip> scripts/verify.sh
```

Checks the acceptance criteria that can be measured right away (key-only SSH, slot, Wi-Fi, cores,
memory, zram, watchdog, temperature, Docker on the docker kernel, ports closed on the LAN)
and lists what depends on time (24 h, 72 h) or on hands-on access to the unit (power loss, rollback).

## Switching kernels (safe ↔ docker)

```bash
HOST=<echo-ip> scripts/flash-boot.sh docker
```

The `boot` partition has no slots: if the new kernel does not come back with SSH within 5 minutes, the script requests
fastboot over the unit's USB console and writes the previous image back. The rootfs must have the rebuilt
driver (rootfs built after `build-kernel.sh docker`); the script checks this first. The same
rootfs works with both kernels: the supervisor only starts `dockerd` on the docker kernel (`DOCKER=auto`).

## On the Echo

```
penguin status | logs [supervisor|docker|boot|firewall] [-f] | settings | set K V | restart | firewall
slotctl status
```

Settings in `/etc/penguin/defaults.conf`, overridden in `/data/penguin/settings.conf`
(`penguin set LAN_PORTS "80 443"` opens those ports on Wi-Fi; `penguin set DOCKER_LAN 1` opens the ports
published by containers; then `penguin firewall`). Logs in `/data/penguin/logs`.

## Updating the rootfs

```bash
scp ../echo-penguin-build/work/out/echo-penguin-rootfs-<v>.tar.gz root@<ip>:/data/techo5-linux/
ssh root@<ip> 'slotctl install /data/techo5-linux/echo-penguin-rootfs-<v>.tar.gz && reboot'
```

It goes to the inactive slot on trial (3 attempts). It is only committed once the supervisor has been up for 5 minutes **and
the network has a default route** (`etc/techo5/trial.conf`); otherwise the unit falls back to the previous slot on its own.

## Way back

- **Kernel**: `flash-boot.sh safe`, or `fastboot flash boot ../echo-penguin-build/work/out/echo-penguin-boot-safe.img`.
- **Bad slot**: falls back on its own; by hand, `slotctl rollback`.
- **LineageOS**: `fastboot flash boot ../echo-penguin-build/techo5/inputs/boot-lineage-18.1-20260904-cronos.img`, then the LineageOS
  zip through TWRP (recovery stays intact) — TECHO5's `docs/install.md`, "To go back to LineageOS".
- **Factory Fire OS**: the TECHO5 installer's full backup of the small partitions in
  `techo5/backups/<serial>/partitions/` (with `SHA256SUMS`; `p9-boot.img` is the original boot).
- **Unit without network**: root console over USB (`/dev/ttyACM*`, gadget 1d6b:0104), `rebootto bootloader`
  goes to fastboot.

## References

echo-penguin stands on the work of these projects; versions and commits are pinned in
[config.env](config.env).

- **[TECHO5](https://github.com/HuskerMinion/techo5)** (MIT) — the boot chain, rescue initramfs,
  slot store (`slotctl`), installer (`tools/install-show.py`), USB console library
  (`tools/techo5lib.py`) and image packer (`tools/linux/mkimage.py`), used unmodified.
  [scripts/mkrootfs.sh](scripts/mkrootfs.sh) and [rootfs/etc/techo5/boot.sh](rootfs/etc/techo5/boot.sh)
  are trimmed forks of its `tools/linux/mkrootfs.sh` and `etc/techo5/boot.sh`;
  [rootfs/usr/local/sbin/rebootto](rootfs/usr/local/sbin/rebootto) is a Python port of its `cmd/rebootto`.
- **[amazon-oss/android_kernel_amazon_mt8163](https://github.com/amazon-oss/android_kernel_amazon_mt8163)**
  (GPL-2.0) — the LineageOS kernel for `cronos` that both kernels are built from, and that
  [kernel/patches/](kernel/patches/) applies to.
- **[amazon-oss/android_kernel_amazon_mt76x8-wifi](https://github.com/amazon-oss/android_kernel_amazon_mt76x8-wifi)**
  — the MediaTek MT7668 Wi-Fi driver source, rebuilt for the docker kernel.
- **LineageOS 18.1 for the Echo Show 5 2nd gen** —
  [unofficial build (XDA)](https://xdaforums.com/t/rom-unofficial-11-cronos-lineageos-18-1-for-the-amazon-echo-show-5-2021.4772598/)
  and the [unlock, root and TWRP guide (XDA)](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-show-5-2nd-gen-2021-cronos.4772596/)
  that installing echo-penguin presupposes.
- **[Alpine Linux](https://alpinelinux.org/)** — the minirootfs, `apk` and the packages in
  [rootfs-packages.txt](rootfs-packages.txt); see also the Alpine wiki on
  [Docker](https://wiki.alpinelinux.org/wiki/Docker).
- **[Arm GNU Toolchain 8.3-2019.03](https://developer.arm.com/downloads/-/gnu-a)** — the aarch64
  cross compiler this 4.9 kernel tree builds with.
- **[Moby `check-config.sh`](https://github.com/moby/moby/blob/master/contrib/check-config.sh)** —
  the list of kernel options Docker needs, behind [kernel/docker.config](kernel/docker.config).
- **[tonistiigi/binfmt](https://github.com/tonistiigi/binfmt)** — QEMU user emulation for building
  the armv7 rootfs on an x86_64 host.
- **[sdat2img](https://github.com/xpirt/sdat2img)** by xpirt — the reference for the Android
  `transfer.list` format; [scripts/sdat2img.py](scripts/sdat2img.py) is a minimal reimplementation.

## License

[MIT](LICENSE), except [kernel/patches/](kernel/patches/), which modifies the Linux kernel and is
GPL-2.0. See [NOTICE](NOTICE) for the code derived from TECHO5 and for what the built images contain.
