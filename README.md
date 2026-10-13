# systemd-examples

Small, self-contained labs for poking at systemd behaviour.

Each example lives in its own directory with a `Dockerfile`, a `Makefile`
and a `README.md`, and runs systemd as PID 1 inside a Docker container. You
only need Docker and `make`. No VM and no changes to the host are required.

## Examples

| Example | What it shows |
|---|---|
| [networkd-wait-online](networkd-wait-online/) | When `systemd-networkd-wait-online` lets `network-online.target` through. An unplugged but managed NIC delays every service that waits for the network until the timeout. Scenarios compare `RequiredForOnline=no`, `--any`, catch-all `.network` files and unmanaged links. |

## Running an example

```bash
cd networkd-wait-online
make demo-all
```

See each example's README for its targets and what to look for.
