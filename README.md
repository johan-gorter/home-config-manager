# Home Assistant homelab — blueprint

Best practices, design decisions and example configuration for running Home
Assistant on a small always-on machine (an old laptop works well), with
Zigbee2MQTT, Mosquitto and an optional wall-mounted kiosk screen.

This repository contains **no install scripts on purpose**. Scripts for this kind
of setup go stale within months: Ubuntu changes its display manager, Docker
changes its packaging, a coordinator moves from USB to Ethernet. What stays
valid is the *reasoning*. So every document here explains what to do, why, and
what goes wrong if you skip it, with example code you adapt by hand.

It is written to be used together with [Claude Code](https://claude.com/claude-code):
open this repo on the server and ask Claude to set things up following these
docs. See [CLAUDE.md](CLAUDE.md).

## Start here

1. [docs/new-install.md](docs/new-install.md) — the checklist, in order
2. [docs/architecture.md](docs/architecture.md) — what runs where, and why

## Topics

| Document | About |
|---|---|
| [architecture.md](docs/architecture.md) | Containers, Compose file, systemd unit, healthchecks |
| [users-and-permissions.md](docs/users-and-permissions.md) | Data directory, groups, setgid + ACL, what is and isn't a security boundary |
| [laptop-as-server.md](docs/laptop-as-server.md) | No sleep, lid, battery as UPS, updates and reboots |
| [zigbee.md](docs/zigbee.md) | Choosing a coordinator, channels, stable device names, monitoring |
| [light-with-fallback.md](docs/light-with-fallback.md) | Lights that keep working when the server is down |
| [thread-matter.md](docs/thread-matter.md) | Thread border router and Matter, and when not to use them |
| [kiosk.md](docs/kiosk.md) | A dashboard screen that boots straight into Home Assistant |
| [remote-access.md](docs/remote-access.md) | Reaching Home Assistant from outside without opening your router |
| [backup.md](docs/backup.md) | Encrypted, append-only, offsite backups |
| [claude-access.md](docs/claude-access.md) | Giving Claude Code safe access to Home Assistant |

Example files are in [`examples/`](examples/).

## Keeping your own house separate

Everything specific to one house — IP addresses, device names, automations,
family accounts, domain names — belongs in a **private** repository, not here.
See [docs/new-install.md](docs/new-install.md#a-private-repo-for-your-house).
