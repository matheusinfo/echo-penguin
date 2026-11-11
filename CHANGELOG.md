# Changelog

Versions are the root filesystem's (`/etc/techo5-release` on the unit, `-V` of `build-rootfs.sh`).
The boot images (kernels) are rebuilt alongside them; the changes to them are listed under the
version that first needed them. Every version below ran on an Echo Show 5 2nd gen.

## Unreleased

## v0.3.2 — 2026-11-11

One voice, and a lighter unit.

- The home clock speaks in the alarm's voice. A tap on it was answered by espeak-ng's robotic voice,
  as Piper needs some 19 s to load and seconds more a phrase; it is now said at once from clips Piper
  rendered ahead: the hours and the minutes once (110 clips, about ten minutes niced in the background
  after the first start or a change of voice, kept in `/data/penguin/speech`), the weather's sentences
  after each fetch. Until they are there a tap says what is ready, or that the voice is being prepared.
- espeak-ng is gone as a voice: `SPEAK_ENGINE` and `SPEAK_VOICE` are no longer settings (lines left
  in `settings.conf` are ignored), `PIPER_VOICE` is the voice everywhere, and an alarm's greeting
  that was not rendered in time is said from the clips. The package stays, for the phoneme data Piper
  reads. An image built with `PIPER=0` has no speech.
- `penguin-sound`: each line of a text is a clip, rendered once (the missing ones of a call by one
  Piper run), trimmed, stored as the speaker takes it and joined when said. `prepare [--keep]`
  renders clips ahead, `say --ready` says only what is there. One Piper at a time. `-e` is accepted
  and ignored.
- `penguin-weather speech --clips` prints the greeting as clips, the time as its hour and its
  minutes; `phrases` lists every clip the clock can need. `line` and `speech` no longer load Python's
  HTTP and TLS modules (half their start).
- `penguin-ui`: the home screen started `ip` on every frame (twice a second, all day) and Display &
  sound started `penguin-sound volume` (Python, then `amixer`): both are now read every 10 s. The
  weather's line is refreshed only while the home screen shows it, a finger on the screen no longer
  runs a whole step per batch of touch events, and a stopwatch left running no longer keeps the loop
  at 10 Hz under the night clock. A missing `penguin-sound` no longer ends the UI at a beep.
- The supervisor asked `docker info` every 15 s (the Docker CLI started and a full report from
  dockerd, a quarter of a core while it ran); it now looks for the process and its socket.
- A `settings.conf` the shell cannot parse (an unclosed quote, edited by hand) ended `boot.sh` before
  the network came up, the supervisor and `penguin set` itself; it is now left out, with a message.
  `penguin set` writes the file whole and renames it, so a power cut cannot drop a setting.
- Boot: the screen and the alarms no longer wait for the network. `boot.sh` joined Wi-Fi, took a
  lease and set the clock before ending, and init starts `penguin-ui` only then: with the router off,
  60 to 130 s without a clock at every boot. That part now runs in the background; the weather's first
  fetch is retried every minute for five.
- A router off for the night no longer restarts the unit every 16 minutes: the reboot after 15
  minutes without an address happens once an outage (`net-reboot` in the log folder marks it until
  the network is back); Wi-Fi is still retried every minute.
- `rebootto` waited its whole 40 s for a supervisor that init had already started again, which could
  start dockerd just before the reboot; it holds the supervisor first (`/run/techo5/hold`).

## v0.3.1 — 2026-11-09

A natural voice for the alarm's greeting.

- Piper, an offline neural voice, in Brazilian Portuguese (`pt_BR-faber-medium`). With
  `SPEAK_ENGINE=piper` the greeting after an alarm is Piper's: it needs about 40 s for a sentence on
  this CPU (18 s of it loading the model), so `penguin-ui` renders it in the background (niced) ten
  minutes before the alarm, saying when the alarm rang, and plays it when the alarm is stopped. Not
  ready in time (an alarm set a minute ahead), it is waited for up to a minute, then espeak-ng says
  the time instead. A tap on the home clock stays espeak-ng (instant). `PIPER_VOICE` chooses the
  voice, from `/usr/share/piper/voices` or `/data/penguin/voices`.
- Piper is only in Alpine's edge/testing, against libraries newer than v3.24's. `scripts/build-piper.sh`
  (run by `build-rootfs.sh`; `PIPER=0` leaves it out) installs it from edge into a scratch root, copies
  `piper_exe`, the 55 libraries it loads and edge's musl loader into `/usr/lib/piper`, and runs it
  through that loader (`/usr/local/bin/piper`), apart from the system's libraries. Versions and the
  voice's SHA-256 are pinned in `config.env`. Tested on the unit first in an armv7 container, then
  natively: 38 s for a sentence, the same. A 64-bit build was faster (26 s) but not enough to change
  the design, and would need Docker's seccomp filter off.
- `penguin-sound say|render -e espeak|piper [-v VOICE]`: `render` writes the WAV without playing it.
  Piper's 32-bit float WAV is read and converted to the speaker's 48 kHz stereo like espeak-ng's.
- `penguin-weather speech -e ENGINE -v VOICE --alarm HH:MM`: the language follows the voice that will
  speak (Piper's voice with `SPEAK_ENGINE=piper`), and `--alarm` says when the alarm rang.

## v0.3.0 — 2026-11-09

A gentler alarm, the weather, a night clock and a sleep diary.

- Gradual wake. `WAKE_LIGHT` minutes before an alarm (default 10) an untouched screen shows a sunrise:
  colours from deep red to warm white through the console's palette (`ESC ] P`, verified on the
  MediaTek framebuffer), the backlight climbing from `BACKLIGHT_DARK` to `BACKLIGHT`, even from
  `Screen off`. The alarm's volume climbs from `WAKE_VOLUME_START` percent of `VOLUME` (80: 40 with the
  default `VOLUME=50`) to `VOLUME` over `WAKE_RAMP` seconds (60); the TAS5805M's control is 1 dB a
  step, about 1.6 dB a percent of the volume scale.
- Weather: `penguin-weather` (Open-Meteo, no account) fetches the forecast for `WEATHER_LAT` /
  `WEATHER_LON` every 30 minutes into `/run/penguin/weather.json`; the home screen shows a line under
  the clock. `penguin-weather set CITY` chooses the place by name.
- Speech: `penguin-sound say TEXT` (espeak-ng, a new package of about 19 MB; voice `SPEAK_VOICE`).
  After an alarm is stopped (`SPEAK_ALARM=1`), and when the home screen's clock is tapped, the time
  and the weather are said in the voice's language (English or Portuguese).
- Night clock: left alone for 30 s in a dark room, the screen shows only a dim red (or amber) clock
  and the next alarm (`NIGHT_CLOCK=auto|on|off`, `NIGHT_COLOR=red|amber`).
- Sleep diary: the screen records the room going dark and lit again (steady for 2 minutes) and the
  alarms' rings and stops in `/data/penguin/sleep-log.jsonl` (`SLEEP_LOG=1`).
  `penguin-sleep` computes the nights (lights off to the alarm stopped, or to the lights on in the
  morning), and Clock > Sleep shows the last seven with their average and the light reading next to
  `LIGHT_DARK`.
- Clock has a fourth tab, Sleep. The home screen fits the weather in by making its six buttons a
  row shorter; the big clock keeps its blank row under the top bar.
- `penguin-sound` never lets ALSA's plug layer convert audio any more. The first speech test played
  espeak-ng's 22050 Hz mono WAV through `plughw:0,23`: it underran on every period, and a page of an
  unrelated file (`penguin-sound` itself) turned to zeros in the page cache, most likely written by
  the AFE driver (the file on disk was intact after a reboot). Speech is now converted to 48 kHz
  stereo in Python and played like the beeps; MP3 was already decoded to that format; a WAV track in
  any other format is refused, so its alarm beeps instead (convert it, or use MP3).
- `penguin set` refuses a value with `"`, `$`, a backquote, a backslash or a control character, and
  a malformed name: `settings.conf` is sourced by the shell as root at boot, so such a value could
  have run as code.

## v0.2.9 — 2026-11-07

Several alarms, and a screen that dims itself when the room goes dark.

- Up to eight alarms. Clock > Alarm lists them in time order, each with an `ON`/`off` switch; tap
  one to change its time, repeat, sound, or to delete it (two taps); `+ Add an alarm` adds one. The
  home screen shows the next alarm due. Alarms due at the same minute ring once, with a track if
  one of them has one.
- The alarms live in `/data/penguin/alarms.json` (`{"alarms": [...]}`), reloaded by the screen
  whenever the file changes: Echo Manager (or anything else) can edit them without restarting
  `penguin-ui`. The single alarm of `alarm.json` becomes the first of the list; that file is left in
  place, so a rollback to an older slot keeps its alarm.
- Automatic brightness (`AUTO_BRIGHTNESS=1`, on by default): the screen follows the room's light
  sensor, fading between `BACKLIGHT_DARK` (default 10) in the dark and `BACKLIGHT` in a lit room.
  `LIGHT_DARK` / `LIGHT_BRIGHT` (defaults 3 and 80) are the sensor readings taken as dark and lit.
  Display & sound shows the reading and sets both levels.
- The light sensor is a JSA1214 behind the vendor `als_ps` driver (named after stk3x1x). The driver
  can leave its measurement off, which freezes the count; `penguin-ui` turns it on (register 0x01 =
  0x04: light on, proximity off) at start and again after ten minutes without the slightest change.
- A screen turned off from outside (backlight 0 over SSH or from Echo Manager) is now treated as
  `Screen off`: a tap or a ringing alarm wakes it. Turned back on from outside, the interface shows
  again.

## v0.2.8 — 2026-11-02

The alarm plays your music, and the big digits are no longer drawn torn.

- The alarm can play music instead of the beep. Copy `.mp3` or `.wav` files into
  `/data/penguin/music/` over SSH and choose one under Clock > Alarm > `Sound:` on the screen,
  which also previews it. The track plays from the start, over and over, until the alarm is stopped
  (ten minutes at most), and the ringing screen shows its name. A track that cannot play falls back
  to the beep. The choice is kept in `/data/penguin/alarm.json`. The timer still beeps.
- `penguin-sound play` takes MP3 as well as WAV, decoded by `mpg123` to 48 kHz stereo. SIGTERM
  stops a playback cleanly: the players first, the held capture node last.
- New package: `mpg123` (with `mpg123-libs`).
- Fixed: the big digits (clock, alarm, stopwatch, timer) were drawn torn whenever the last digit
  was a 1, 2, 5, 6 or 7, e.g. the alarm at 05:25. Each line was trimmed of its trailing blanks and
  then centered on its own, so lines that ended in a glyph's blank columns moved right. The panel,
  long suspected, was never at fault.
- Fixed: `penguin cleanup --yes` left an untagged image whose child image it had just removed; it
  took a second run. It now prunes again while that still deletes images.

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
