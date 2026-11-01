export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PS1='echo-penguin:\w # '
export STORE=/store
# The Docker CLI's config on userdata: /root is read-only.
export DOCKER_CONFIG=/data/penguin/docker-cli

# Screen mirror (SCREEN_MIRROR, /etc/penguin/defaults.conf): an interactive login (SSH or the USB
# console) runs under script(1), which copies everything shown in it to the panel's log console
# (tty2 under the touch interface, SCREEN_UI=1; else tty1). PENGUIN_MIRROR stops the inner login
# shell from doing it again.
if [ -z "$PENGUIN_MIRROR" ] && [ -t 0 ] && [ -x /usr/bin/script ]; then
	eval "$(. /etc/penguin/defaults.conf; [ -r /data/penguin/settings.conf ] && . /data/penguin/settings.conf
		echo "SCREEN_MIRROR=$SCREEN_MIRROR SCREEN_UI=$SCREEN_UI")"
	t=/dev/tty1; [ "$SCREEN_UI" = 1 ] && [ -x /usr/local/bin/penguin-ui ] && t=/dev/tty2
	if [ "$SCREEN_MIRROR" = 1 ] && [ -w $t ]; then
		export PENGUIN_MIRROR=1
		from="USB console"; [ -n "$SSH_CONNECTION" ] && from="SSH from ${SSH_CONNECTION%% *}"
		printf '\n--- %s, %s ---\n' "$from" "$(date '+%H:%M:%S')" > $t 2>/dev/null
		exec /usr/bin/script -q -f -c '/bin/sh -l' $t
	fi
fi
