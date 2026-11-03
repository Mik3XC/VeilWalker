#!/bin/sh
# Runs tor (onion service) and the API in one Railway container. /data is a Railway volume.
set -e
mkdir -p /data/tor/hs
# tor drops to the unprivileged debian-tor user (torrc: User), so it must own its state and onion keys.
chown -R debian-tor:debian-tor /data/tor
chmod 700 /data/tor /data/tor/hs
tor -f /etc/tor/torrc &
# Print the onion address once it exists so it can be copied into TorManager.ONION_BASE_URL.
( for i in $(seq 1 60); do [ -f /data/tor/hs/hostname ] && echo "ONION: $(cat /data/tor/hs/hostname)" && break; sleep 2; done ) &
exec trailbound-api
