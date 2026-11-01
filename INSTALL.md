# Installing echo-penguin, from a locked Echo Show 5

Step by step, from an Echo Show 5 2nd gen straight out of the box (locked, running Fire OS) to the
same unit running echo-penguin: Alpine Linux with Wi-Fi, SSH, Docker and a touch screen.
Each step ends with a **Check:** line. Don't start the next step until the check passes.

> [!WARNING]
> This **erases Android** from the unit and depends on a bootloader exploit made by others. It is
> at your own risk. Steps 2 and 3 follow other projects' guides: read those guides, not only the
> summary here. This project is not affiliated with or endorsed by Amazon.

Placeholders: `<echo-ip>` is the unit's address on your network, `<serial>` its serial number
(`fastboot devices` or `adb devices` shows it).

## Overview

| Step | What | Time |
|---|---|---|
| 1 | Check the model and gather what you need | 10 min |
| 2 | Unlock the bootloader (amonet-cronos) | 30 min |
| 3 | Install LineageOS 18.1, the exact build listed below | 20 min |
| 4 | Prepare the PC and build echo-penguin | 1 h, mostly unattended |
| 5 | Install echo-penguin | 15 min |
| 6 | Verify, and switch to the Docker kernel | 15 min |

## 1. What you need

**The Echo:** an Echo Show 5 **2nd gen** (2021, codename `cronos`, model **C76N8S**). The 1st gen
Show 5, the Show 8 and the 3rd gen Show 5 are other boards and are **not** supported. You also need
its power adapter (keep it on mains power while flashing) and a USB **data** cable to the PC.

**The PC:** Linux on x86-64 (a live USB works for the unlock), about 25 GB free, internet access,
and:

```bash
# Debian/Ubuntu names; use your distribution's equivalents
sudo apt install git python3 python3-brotli make gcc bc curl e2fsprogs util-linux \
                 adb fastboot docker.io qemu-user-static binfmt-support
sudo usermod -aG dialout,docker "$USER"     # USB console and Docker without sudo; log in again
```

An SSH key for the unit:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/techo5      # echo-penguin looks for ~/.ssh/techo5.pub first
```

**Check:** `fastboot --version`, `adb --version` and `docker run --rm hello-world` all work.

## 2. Unlock the bootloader

The Echo's bootloader is locked. It is opened by **amonet-cronos**, an exploit that enters the
MediaTek boot ROM. It is *not* `fastboot flashing unlock`. Follow the thread for every detail:

- Guide: [[UNLOCK][ROOT][TWRP][UNBRICK] Echo Show 5 2nd Gen (cronos)](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-show-5-2nd-gen-2021-cronos.4772596/) (XDA)
- Source: [R0rt1z2/amonet, branch mt8163-cronos](https://github.com/R0rt1z2/amonet/tree/mt8163-cronos)

In short, as TECHO5's getting-started guide puts it: with the Show on mains power, hold all three
buttons until the screen says `=> FASTBOOT mode`, connect USB, and run the fastbrick step from the
thread. The unit reboots into TWRP on its own; don't interrupt it.

- Use **amonet-cronos v2.0.1 or later**. An older one can leave the bootloader locked while
  everything else looks fine. The first sign comes much later, when writing the boot image fails
  with `the command you input is restricted on locked hw`.
- Already unlocked with 1.x (TWRP 3.2.3, `fastboot getvar product` says `CHECKERS`)? Flash
  `amonet-cronos-v2.0.1.zip` in TWRP, as the thread describes.

**Check:** the unit boots into TWRP, and in fastboot (all three buttons held at power-on, as in the
unlock, or `adb reboot bootloader` from TWRP):

```bash
fastboot getvar unlock_status    # unlock_status: true
fastboot getvar product          # product: CRONOS
```

## 3. Install LineageOS 18.1

echo-penguin keeps two things from LineageOS: its **Wi-Fi driver and firmware** (the "vendor tree"),
and the **Wi-Fi network** you join in it. The driver only loads on the kernel it was built with, so
the build matters:

- Guide: [[ROM][UNOFFICIAL][11][cronos] LineageOS 18.1 for the Echo Show 5 (2021)](https://xdaforums.com/t/rom-unofficial-11-cronos-lineageos-18-1-for-the-amazon-echo-show-5-2021.4772598/) (XDA)
- Zip, **exactly this build**: `cronos` v0.4,
  [lineage-18.1-20260904-UNOFFICIAL-cronos.zip](https://github.com/amazon-oss/releases/releases/tag/lineage-18.1-cronos-v0.4).
  Newer builds (2026-10-14, v0.5 and later) have another kernel and are not supported. Keep the zip:
  the build needs it too (step 4).

Install it from TWRP as the thread says, then in LineageOS:

1. Join your Wi-Fi network.
2. Settings → About → tap **Build number** seven times.
3. Developer options: turn on **USB debugging** and **Rooted debugging**; accept the PC's key.

**Check:** LineageOS boots, and `adb devices` lists the unit as `device`.

## 4. Prepare the PC and build

```bash
git clone https://github.com/<owner>/echo-penguin && cd echo-penguin
mkdir -p ../echo-show && cp ~/Downloads/lineage-18.1-20260904-UNOFFICIAL-cronos.zip ../echo-show/
scripts/build-all.sh
```

`build-all.sh` fetches every input at its pinned commit (TECHO5, the kernel source, the Wi-Fi driver
source, the toolchain, Alpine), builds both kernels, both boot images and the root filesystem. All of
it goes into `build/`, which git ignores. It refuses to produce a kernel the Wi-Fi driver would not
load on.

- Building the root filesystem runs ARM package scripts under QEMU. If it stops with *no qemu-arm
  binfmt handler*, register it (this lasts until the PC reboots):
  `docker run --privileged --rm tonistiigi/binfmt:qemu-v9.2.2 --install arm`
- `LINEAGE_ZIP=/path/to/the.zip` points the build at a zip outside `../echo-show/`.

**Check:** `ls build/work/out/` lists `echo-penguin-boot-safe.img`,
`echo-penguin-boot-docker.img` and `echo-penguin-rootfs-<version>.tar.gz`.

## 5. Install

With the unit running LineageOS and connected by USB:

```bash
sudo systemctl stop ModemManager          # it grabs the unit's USB console otherwise (until the PC reboots)
scripts/install.sh safe --dry-run         # checks the unit, the zip and the images; writes nothing
scripts/install.sh safe                   # asks once, then erases LineageOS
```

The installer backs up the LineageOS boot image, flashes echo-penguin's, saves the unit's vendor
tree, turns the LineageOS system partition into the slot store, installs the system into slot `a`,
copies your SSH key and follows the first boot. It uses the Wi-Fi network LineageOS had saved. Add
`--wifi "<network>"` to give another one. **Keep the cable in and the unit on mains power** until it
says it is done.

The screen shows the kernel's messages while the unit boots, then the touch interface: a clock and
six buttons.

**Check:** the screen shows the echo-penguin home screen, and
`ssh -i ~/.ssh/techo5 root@<echo-ip>` logs in. Network & SSH on the screen shows the address.

If the install stops halfway (the unit sits on a **RESCUE** screen), it can be finished over the USB
console: `ECHO_SERIAL=<serial> scripts/finish-install.sh`. See [Troubleshooting](README.md#troubleshooting).

## 6. Verify, and turn on Docker

```bash
HOST=<echo-ip> scripts/verify.sh              # PASS / FAIL / WARN for each check
HOST=<echo-ip> scripts/flash-boot.sh docker   # the kernel with container support
```

The first install uses the **safe** kernel, with LineageOS's own Wi-Fi driver. The **docker** kernel
uses a Wi-Fi driver rebuilt from source. If it does not come back on SSH within five minutes,
`flash-boot.sh` puts the safe kernel back by itself.

A new system slot confirms itself once it has run five minutes with a network. Until then, a reboot
that fails falls back to the previous slot.

**Check:** `verify.sh` ends with no `FAIL`, and on the unit `docker run --rm alpine echo ok` prints
`ok`. The checks that need time or hands on the unit (24 h, 72 h, power cut, Wi-Fi outage) are listed
at the end of `verify.sh`'s output.

## Using it

- **The screen:** tap the buttons. **Logs** shows kernel errors, the boot log and every SSH or USB
  console session as it happens. **System** shows CPU, RAM and storage. **Network & SSH** shows the
  address, Wi-Fi and the authorized keys. **Clock** has an alarm, a stopwatch and a timer.
  **Installed** lists Docker and the main packages. **Display & sound** sets brightness and volume,
  and can turn the screen off (a tap brings it back). The volume buttons on top work too.
- **SSH:** `ssh -i ~/.ssh/techo5 root@<echo-ip>`, then `penguin status`, `penguin settings`,
  `penguin set KEY VALUE`. The full list is in the [README](README.md#using-the-echo).
- **Sound:** `penguin-sound beep`, `penguin-sound play file.wav`, `penguin-sound volume 60`.

## Things that look broken but are not

- **The unit reboots on its own within a few minutes after an update.** If the new slot does not
  settle, it is retried, then dropped for the previous one. `slotctl status` says which one runs.
- **`ssh` warns that the host key changed** after the first install or a rescue boot. Check the key
  on the screen (Network & SSH → Host key) before you accept the new one.
- **Never add parameters to the boot image's kernel command line** (`SCREEN_CMDLINE` in
  `config.env`). The bootloader's line is already near its 1024-byte limit. A longer one hangs the
  unit at the boot logo on every warm reboot, and only a power cut gets it past that.

## The way back

TWRP stays in `recovery`: boot it (the unlock thread gives the way in) and flash the LineageOS zip. That rewrites the system partition, and Android is back. Details in the
[README](README.md#the-way-back).
