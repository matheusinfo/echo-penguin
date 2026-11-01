# Changelog

Versions are the root filesystem's (`/etc/techo5-release` on the unit, `-V` of `build-rootfs.sh`).
The boot images (kernels) are rebuilt alongside them; the changes to them are listed under the
version that first needed them. Every version below ran on an Echo Show 5 2nd gen.

## v0.2.7 — 2026-11-01

- `penguin cleanup` lists what the unit no longer needs: installed rootfs tarballs, test files left
  in `/data/penguin`, stopped containers no compose project owns, untagged images and the build
  cache. `--yes` removes them; `--slot` adds the inactive slot (only once the running one is good).

## v0.2.6 — 2026-11-01

An alarm that repeats, and taps that no longer crash the screen.

- The alarm repeats every day, Monday to Friday, Saturday and Sunday, or rings once and turns
  itself off (`Repeat` on the Clock screen). It used to ring every day with no way to tell.
- Fixed: tapping the same spot over and over (Min +1, Min -1) crashed the interface back to the
  home screen. The kernel sends no position that equals the last one, and the interface lost it.

## v0.2.5 — 2026-11-01

SSH you can restrict and switch off.

- `SSH_ALLOW`: only the listed computers (MAC addresses, or IPv4/IPv6 addresses and networks) reach
  port 22. `penguin ssh allow here` adds the current computer by its MAC, `penguin ssh deny` removes
  one, and `penguin ssh allow any` clears the list. Both refuse a list that would lock out the
  session running them.
- `SSH=off` (`penguin ssh off`, or Network & SSH on the screen): dropbear stops and port 22 closes.
  Fixed: the network watch loop used to start dropbear again behind the closed port.
- dropbear runs with `-s -g -T 3 -k`, and new SSH connections are limited per source (6, then 6 a
  minute).
- `verify.sh` checks dropbear's options and warns while SSH is open to the whole Wi-Fi.

## v0.2.2 — 2026-11-01

- Fluid clock. MediaTek's display needs a frame trigger after each redraw, and it drops to an idle
  mode after 1 s without one. The interface now pans after every frame and every 0.45 s.

## v0.2.1 — 2026-11-01

- The Logs screen shows the log console under the interface's header (`< Back`, `System`).

## v0.2.0 — 2026-11-01

A touch screen and sound.

- `penguin-ui` on the panel: a large clock and Logs, System, Network & SSH, Clock (alarm, stopwatch,
  timer), Installed, and Display & sound (brightness, volume, screen off). The volume buttons work
  too. Plain text on the framebuffer console, Python's standard library only. `SCREEN_UI=0` turns
  it off.
- `penguin-sound` (beep, play, volume) on the speaker. It holds open the second PCM device that the
  MediaTek playback driver needs, or the kernel panics. `VOLUME` is set at boot.
- The log console (kernel errors, boot log, mirrored sessions) moves to tty2.
- Clean-up: `wireless-tools` and `htop` removed, `alsa-utils` added, Python's unused parts trimmed.
- Step-by-step install guide from a locked unit: [INSTALL.md](INSTALL.md).

## v0.1.3 — 2026-10-31

Linux on the screen.

- Kernels: VT and framebuffer console, plus three patches. One makes `mtkfb` keep its palette at
  32 bpp, so text is no longer black on black. The others make fbcon start rotated clockwise and
  choose the 12x22 font. The penguin logo is gone.
- Fixed: warm reboots hung at the boot logo. The extra kernel command-line options pushed the
  bootloader past its 1024-byte limit. The boot image's command line is back to its own 150 bytes.
- Kernel and boot messages on the screen, with interactive SSH and USB-console sessions mirrored
  there (`SCREEN_MIRROR`). The watchdog's every-10-s warning stays off the screen
  (`SCREEN_LOGLEVEL`). The panel stays on (`BACKLIGHT=90`).
- The root filesystem's own files are owned by root and are not group- or world-writable. The build
  now fails if that ever slips.
- `verify.sh` no longer reports idle cores or clean reboots as problems.

## v0.1.1 — 2026-10-31

- First install on the unit: safe kernel, then the docker kernel with the rebuilt Wi-Fi driver,
  Docker, and SSH by key.
- Fixed in TECHO5's library at build time: the rescue's NTP step could kill PID 1.
- `flash-boot.sh` finds `rebootto` over SSH and no longer hangs when the unit drops the connection.

## v0.1.0 — 2026-10-31

- First build: two kernels (safe with the vendor Wi-Fi driver, docker with a rebuilt one), TECHO5's
  boot chain and A/B slots, Alpine 3.24 with Docker, firewall, watchdog, zram and the supervisor.
