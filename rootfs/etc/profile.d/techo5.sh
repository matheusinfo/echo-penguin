export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PS1='echo-penguin:\w # '
export STORE=/store
# The Docker CLI's config on userdata: /root is read-only.
export DOCKER_CONFIG=/data/penguin/docker-cli

# Screen mirror (SCREEN_MIRROR, /etc/penguin/defaults.conf): an interactive login (SSH or the USB
# console) runs under script(1), which copies everything shown in it to the panel's terminal (tty1).
# PENGUIN_MIRROR stops the inner login shell from doing it again.
if [ -z "$PENGUIN_MIRROR" ] && [ -t 0 ] && [ -w /dev/tty1 ] && [ -x /usr/bin/script ]; then
	SCREEN_MIRROR=$(. /etc/penguin/defaults.conf; [ -r /data/penguin/settings.conf ] && . /data/penguin/settings.conf; echo "$SCREEN_MIRROR")
	if [ "$SCREEN_MIRROR" = 1 ]; then
		export PENGUIN_MIRROR=1
		from="USB console"; [ -n "$SSH_CONNECTION" ] && from="SSH from ${SSH_CONNECTION%% *}"
		printf '\n--- %s, %s ---\n' "$from" "$(date '+%H:%M:%S')" > /dev/tty1 2>/dev/null
		exec /usr/bin/script -q -f -c '/bin/sh -l' /dev/tty1
	fi
fi
