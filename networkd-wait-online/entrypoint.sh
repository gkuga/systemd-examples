#!/bin/sh
# Lay the chosen scenario's /etc over the image and hand PID 1 to systemd.
set -eu

scenario="${SCENARIO:-stuck}"
if [ ! -d "/scenarios/$scenario" ]; then
    echo "unknown scenario: $scenario (have: $(ls /scenarios | tr '\n' ' '))" >&2
    exit 1
fi
if [ -d "/scenarios/$scenario/etc" ]; then
    cp -a "/scenarios/$scenario/etc" /
fi

# systemd-networkd waits for udev to initialize each link unless /sys is
# read-only, which is how it recognizes a container. --privileged mounts /sys
# read-write and there is no udev here, so remount it to keep links from
# sitting in "pending" forever. /sys/fs/cgroup is a separate mount and stays
# writable for systemd.
mount -o remount,ro /sys

exec /sbin/init
