FROM debian:bookworm

# Tell systemd it is running inside a container.
ENV container=docker

RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus iproute2 dnsmasq-base \
    && rm -rf /var/lib/apt/lists/*

# Units that only make noise (or fail) inside a container.
RUN systemctl mask \
        getty.target console-getty.service \
        systemd-logind.service systemd-resolved.service \
        systemd-timesyncd.service apt-daily.timer apt-daily-upgrade.timer

COPY base/ /
COPY scenarios/ /scenarios/
COPY entrypoint.sh /entrypoint.sh

# systemd-networkd is disabled on Debian by default. Enabling it also enables
# systemd-networkd-wait-online.service through its Also= line.
RUN systemctl enable systemd-networkd.service fake-cables.service demo-app.service

# systemd stops cleanly on SIGRTMIN+3, not SIGTERM.
STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/entrypoint.sh"]
