# systemd-networkd-wait-online

A small lab for seeing when `systemd-networkd-wait-online` lets
`network-online.target` through, and what happens to a service that waits for
it.

The setup mirrors a box with two NICs where only one is cabled:

- `eth0` is plugged in and configured.
- `eth1` is unplugged but still managed by systemd-networkd (it has DHCP on).
- `demo-app.service` stands in for an application with
  `Wants=network-online.target` and `After=network-online.target`.

With stock settings, wait-online waits for `eth1` until it times out, and
`demo-app` starts only after that timeout. The scenarios show which
configurations cause that wait and which avoid it.

## Quick start

Docker and `make` are all you need.

```bash
make demo-all                 # run every scenario and print a report for each
make demo SCENARIO=stuck      # run one scenario
make list                     # list the scenarios
```

A report looks like this (trimmed):

```
=== scenario: stuck

=== networkctl list
IDX LINK     TYPE     OPERATIONAL SETUP
 11 eth0     ether    routable    configured
 12 eth1     ether    no-carrier  configuring

=== .network file per link
eth0: /etc/systemd/network/05-eth0.network
eth1: /etc/systemd/network/10-eth1.network

=== wait-online command line
/lib/systemd/systemd-networkd-wait-online --timeout=20

=== result
systemd-networkd-wait-online: exit-code (failed)
network-online.target reached after: 20s
demo-app started after:              20s
```

## Scenarios

The timeout is shortened from the default 120s to 20s (see
[Notes](#notes)), so "20s" below means "waited until the timeout".

| Scenario | What eth1 gets | wait-online | demo-app starts after |
|---|---|---|---|
| `stuck` | `10-eth1.network` with `DHCP=yes` | fails on timeout | 20s |
| `catch-all` | no eth1 file, but `99-default.network` matches it | fails on timeout | 20s |
| `required-for-online-no` | `05-eth1.network` with `RequiredForOnline=no`, sorting before `10-eth1.network` | succeeds | ~1s |
| `any` | same as `stuck`, but wait-online runs with `--any` | succeeds | ~1s |
| `unmanaged` | no `.network` file matches eth1 | succeeds | ~1s |

What each one shows:

- **stuck**: a managed link that never finishes configuring blocks
  wait-online. `eth1` sits in `no-carrier` / `configuring` because DHCP
  never completes without a cable. When wait-online times out, it fails, but
  `network-online.target` is still reached and `demo-app` starts. This is
  because the dependency is only `Wants=`, not `Requires=`.
- **catch-all**: deleting the eth1-specific file does not help when a
  catch-all `.network` file still matches `eth1`.
- **required-for-online-no**: `[Link] RequiredForOnline=no` takes `eth1`
  off wait-online's list while keeping DHCP on it. A `.network` file is
  picked by the first match in lexical order, which is why `05-` wins over
  `10-`.
- **any**: `--any` is satisfied as soon as one link is online, so `eth0`
  alone is enough.
- **unmanaged**: links that systemd-networkd does not manage (`SETUP`
  shows `unmanaged`) are ignored by wait-online.

## How wait-online decides

Without options, `systemd-networkd-wait-online` finishes when both of these
hold:

1. Every link that is **managed by systemd-networkd** (a `.network` file
   matches it) and **required for online** (`RequiredForOnline=` is not
   `no`) has finished configuring. In `networkctl`, its `SETUP` column is
   `configured` or `failed`.
2. At least one of those links is **online**, meaning its `OPERATIONAL`
   column is at least `degraded`.

If that does not happen within `--timeout` (default 120s), it exits with
status 1. Whether internet access works is never checked. Only the link
states that systemd-networkd reports matter.

The knobs:

| Where | Setting | Effect |
|---|---|---|
| `.network` | `[Link] RequiredForOnline=no` | do not wait for this link |
| `.network` | `[Link] RequiredForOnline=routable` | wait until this link is at least `routable` |
| wait-online | `--any` | done when any one link is online |
| wait-online | `--interface=eth0` | wait only for the given links |
| wait-online | `--ignore=eth1` | never wait for the given links |
| wait-online | `--operational-state=routable` | raise the bar for "online" |
| wait-online | `--timeout=N` | give up after N seconds (0 = never) |

The wait-online options are set with a drop-in that replaces `ExecStart=`.
See `base/etc/systemd/system/systemd-networkd-wait-online.service.d/10-args.conf`.

## Poking at it by hand

```bash
make up SCENARIO=stuck        # boot it and leave it running
make shell SCENARIO=stuck     # shell inside
```

Inside the container, while wait-online is still waiting:

```bash
systemctl list-jobs           # demo-app and network-online.target are "waiting"
networkctl list
systemctl status systemd-networkd-wait-online
```

Plug the cable in during boot. eth1 gets a DHCP lease from a server on the
other end, and wait-online finishes right after that, without waiting for
the timeout:

```bash
make up SCENARIO=stuck && sleep 5 && make plug SCENARIO=stuck
make wait report SCENARIO=stuck
```

`make unplug` pulls the cable out again, and `make down SCENARIO=...`
removes the container. `make clean` removes all containers and the image.

## How it works

- **systemd as PID 1 in Docker.** The container runs privileged with its own
  cgroup namespace. `entrypoint.sh` overlays the scenario's `etc/` onto the
  image and then `exec`s `/sbin/init`.
- **Fake cables.** `fake-cables.service` runs before systemd-networkd. It
  creates `eth0` and `eth1` as veth pairs whose other ends live in a network
  namespace called `switch`. A veth only has carrier while its peer is up, so
  the `eth1` peer is left down to play an unplugged cable. The container runs
  with `--network none`, so systemd-networkd only sees `lo`, `eth0` and
  `eth1` as real NICs.
- **Plugging in.** `plug-eth1` brings the `eth1` peer up and starts
  `dnsmasq` in the `switch` namespace as a DHCP server.
- **The report.** `report` prints `networkctl`, the `.network` file each link
  uses, the wait-online command line, and the time from systemd start until
  `network-online.target` and `demo-app` became active.

## Notes

- **Timeout.** The default timeout is 120s. The base drop-in shortens it to
  20s so the waiting scenarios finish quickly. Everything else is stock.
- **`/sys` is remounted read-only.** systemd-networkd waits for udev to
  initialize every link unless `/sys` is read-only, which is how it
  recognizes a container. `--privileged` mounts `/sys` read-write and there
  is no udev in the container, so without the remount every link stays
  `pending` forever.
- **`IPv6AcceptRA=no` on eth0.** Nothing on the `switch` side sends IPv6
  router advertisements. With RA acceptance on (the default), networkd keeps
  `eth0` in `configuring` for about 13s while it solicits one, which would
  blur the timings.
- **`Name=eth*` in the catch-all scenario.** A real box would typically use
  `Name=!lo`. Inside the container, the kernel also creates fallback tunnel
  devices (`tunl0`, `gre0`, `sit0`, ...), and `!lo` would pull those in too.
- **systemd version.** The image is Debian bookworm (systemd 252). Older
  systemd lacks some wait-online options, such as `-4` / `-6`; check
  `systemd-networkd-wait-online --help` on the target system.
