# CLAUDE.md

Claude Code manages and configures this homelab server. The user has basic Linux
knowledge — prefer clear explanations, avoid jargon, and run commands directly
rather than asking the user to do so.

> **The `scripts/` directory is obsolete. Do not run `install.sh`.**
> The running system was built by hand (see `docs/install-log.md`) and differs
> from those scripts in almost every detail: different data directory, different
> Docker packages, different Zigbee adapter and transport, no kiosk. Running
> `install.sh` would write a second, conflicting stack. Treat `scripts/` as a
> record of requirements only; `ROADMAP.md` supersedes it.

## Environment

- OS: Ubuntu 26.04.1 LTS (`resolute`), kernel 7.0.0-38-generic, amd64
- Hostname: `sticker`. (*silver* is the previous laptop, kept for a future
  standby role — see ROADMAP B4. Do not confuse the two.)
- Laptop, Intel GPU, eDP panel, **no Ethernet port** (WiFi `wlo1` only)
- Host IP: 192.168.68.120/24, gateway 192.168.68.1. **DHCP reservation set** in
  the TP-Link Deco mesh, as is the coordinator's 192.168.68.109
- Passwordless sudo is configured for `jgo` — use `sudo` freely
- Claude runs in the desktop app (deb package `claude-desktop`, apt repo at
  downloads.claude.ai). There is **no** `claude` CLI on this machine; update with
  `sudo apt install --only-upgrade claude-desktop`.

## Users and permissions

| User | Purpose |
|---|---|
| `jgo` | Administration, sudo. Member of group `homeassistant` |
| `homeassistant` (uid 997, system user, nologin) | Owns the service data |
| `kiosk` | **Not created yet** — see ROADMAP 2 and 3 |

Data lives in `/srv/homeassistant`, owned `root:homeassistant`, mode `750`, with
the **setgid bit on every directory** and a **default ACL** `g:homeassistant:rwX`.

This combination is what makes the whole arrangement work, and it is easy to
break: the containers run as root and write files as root, so without setgid plus
the default ACL, `jgo` could not edit anything the containers create. Mosquitto
additionally has ACLs for uid 1883 on its `data` and `log` directories, because
that container drops to a non-root user.

Note that `homeassistant` is **not a security boundary** — see ROADMAP 6. Docker
runs as root and starts the containers as root. The user exists for file
ownership; the group is what does the actual work.

After changing group membership, log out and back in — a running shell keeps its
old groups.

## Layout

```
/srv/homeassistant/
  docker-compose.yml
  homeassistant/            # HA config, .storage, database
  zigbee2mqtt/              # configuration.yaml, coordinator_backup.json
  mosquitto/{config,data,log}
/etc/systemd/system/homelab.service
/etc/systemd/logind.conf.d/99-homelab.conf
/etc/udev/rules.d/99-zigbee.rules      # present but currently unused (see below)
```

## Services

Docker comes from **Ubuntu's own packages** (`docker.io` 29.1.3,
`docker-compose-v2` 2.40.3), not Docker's upstream repository — one fewer
third-party repo and key, and security updates arrive through the normal channel.

| Container | Image | Notes |
|---|---|---|
| `homeassistant` | `ghcr.io/home-assistant/home-assistant:stable` (2026.10.0) | `network_mode: host`, **no** `privileged`, only `cap_add: [NET_RAW, NET_ADMIN]` |
| `mosquitto` | `eclipse-mosquitto:2` | Published on **127.0.0.1:1883 only** |
| `zigbee2mqtt` | `koenkk/zigbee2mqtt` (2.14.2) | Talks to the coordinator over TCP |

`homelab.service` (oneshot, `RemainAfterExit`) is enabled and runs
`docker compose up -d`. Verified: Home Assistant and Mosquitto came back by
themselves after a reboot on 2026-10-09.

Power management is disabled so the laptop can act as a server:
`sleep.target`, `suspend.target`, `hibernate.target` and `hybrid-sleep.target`
are masked, and logind ignores the lid switch on all power sources.

## Zigbee

Coordinator: **SMLIGHT SLZB-MR5U** — ESP32-S3 core running SLZB-OS, with two
EFR32MG24 radios (Silicon Labs), two +5 dB antennas, Ethernet-first with PoE or
USB-C power.

- Connected over **Ethernet**, powered by a USB-C adapter
- Device IP **192.168.68.109**, Zigbee socket on port **6638**, web UI on port 80
- Zigbee2MQTT: `adapter: ember`, `port: tcp://192.168.68.109:6638`
- EmberZNet 7.4.2 [GA], EZSP 13
- **Channel 25**, PAN ID `0x1a62` (6754). Chosen because the house WiFi
  (`gorterm`) sits on 2.4 GHz channel 8 and the neighbours occupy 2, 4 and 7 —
  the whole lower half of the band is busy. Changing this later means re-pairing
  every device.

**USB-C cannot carry Zigbee on this model.** That port exposes the ESP32-S3's
"SM Console", a text interface (`wipe`, `test_mode`, `device_ip`, `otbr_init`,
`otbr_deinit`). This was established empirically: the console answered
Zigbee2MQTT's EZSP/ASH reset frames with `Unknown cmd: <...>`. The udev rule in
`/etc/udev/rules.d/99-zigbee.rules` dates from that attempt and is harmless but
currently does nothing. It is kept because it still correctly matches the
device's USB serial (`50:78:7D:D7:E3:B0`) should console access be needed again.

The Ethernet interface uses MAC `52:78:7D:D7:E3:B0` — the same base MAC with the
locally-administered bit set, which is how an ESP32 derives it. Useful when
hunting for the device on the network.

## Web interfaces

| | URL | Auth |
|---|---|---|
| Home Assistant | http://localhost:8123 | Account required |
| Zigbee2MQTT | http://localhost:8080 | **None** — see Known issues |
| Coordinator | http://192.168.68.109 | Set in SLZB-OS |

## Common tasks

```bash
sudo sh -c 'cd /srv/homeassistant && docker compose up -d'    # start
sudo sh -c 'cd /srv/homeassistant && docker compose down'     # stop
sudo docker logs -f zigbee2mqtt                               # follow logs
sudo docker compose -f /srv/homeassistant/docker-compose.yml ps
```

Adding devices and integrations happens in the **web interface**, not in files.
`\.storage/` is HA's internal state and must never be hand-edited. File access is
only for YAML: automations, templates, custom components.

## Known issues and gaps

- **Zigbee2MQTT's frontend listens on 0.0.0.0:8080 with no authentication.**
  Anyone on the WiFi can open it, control every device and enable `permit_join`.
  Same class of problem as the Mosquitto exposure that was already fixed. Bind it
  to 127.0.0.1 or put authentication in front of it.
- **The Deco mesh must not roam across 2.4 GHz channels.** Deco defaults to
  automatic channel selection, and an access point that drifts onto channel 11
  lands right against Zigbee channel 25 (2475 MHz sits just above channel 11's
  upper edge). The symptom is random, unexplained Zigbee dropouts across the
  whole house. Pin the 2.4 GHz band to channel 1 or 6 in the Deco app.
- **No backup yet.** `coordinator_backup.json` exists and holds the network key;
  it lives on a single SSD. The agreed design (restic to a Hetzner Storage Box)
  is in ROADMAP 7 and is not built.
- **Bluetooth does not work in HA.** The container cannot reach the host's D-Bus,
  so the integration throws errors in the log. Harmless until Bluetooth devices
  are needed; fixed with a D-Bus mount.
- **No kiosk, no InfluxDB, no Tailscale.** See ROADMAP.

## Functional requirements

**Important lights must have a physical fallback.** Lights in essential spaces
(toilets, hallways, stairs) must be controllable through a direct Zigbee bind, so
they keep working when the network, the server or Zigbee2MQTT is down. Use
`genOnOff` cluster binds from button to lamp. See `docs/light-with-fallback.md`.

Naming convention: `{Room} lamp` / `sensor` / `knop`. Apply it from the first
device onwards — renaming later propagates into every automation.

## Planning

`ROADMAP.md` holds what is agreed and what is still open. Decisions settled so
far: Docker stays, backups go to a Hetzner Storage Box via restic, long-term
sensor data goes to InfluxDB for a future MPC controller, remote access is
Tailscale (no paid subscription), and the Zigbee network is built from scratch
with nothing migrated.
