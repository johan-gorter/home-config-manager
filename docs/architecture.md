# Architecture

```
                     ┌──────────────── server (/srv/homeassistant) ────────────────┐
 phone / browser ──► │ homeassistant  (host network, :8123)                        │
                     │      │ MQTT 127.0.0.1:1883                                   │
                     │ mosquitto ◄── zigbee2mqtt (:8080 frontend, auth_token)       │──TCP/USB──► Zigbee coordinator
                     │ influxdb (127.0.0.1:8086)     matter-server (127.0.0.1:5580) │
                     └──────────────────────────────────────────────────────────────┘
```

All services run as Docker containers from one Compose file,
[`examples/docker-compose.yml`](../examples/docker-compose.yml), in
`/srv/homeassistant`. A systemd unit
([`examples/systemd/homelab.service`](../examples/systemd/homelab.service)) runs
`docker compose up -d` at boot.

## Why these choices

**Docker from Ubuntu's packages** (`docker.io`, `docker-compose-v2`), not Docker's
upstream repository: one fewer third-party repository and key, and security
updates arrive through the normal channel with unattended-upgrades.

**Docker at all,** rather than HA Core in a Python venv or HA OS: containers are
easy to update and roll back, and the host stays a normal Ubuntu machine that
can also run a kiosk. Rootless Podman was considered and dropped: it cannot do
host networking, which HA needs for discovery.

**Data in `/srv/homeassistant`,** not in a home directory or inside a git
checkout. It is service data; see [users-and-permissions.md](users-and-permissions.md).

**Zigbee2MQTT rather than ZHA:** broader device support, and the direct binds
needed for [lights with a fallback](light-with-fallback.md) are much easier to
set up. The price is Mosquitto as an extra container.

## Container rules

- **No `privileged: true`.** Home Assistant gets `cap_add: [NET_RAW, NET_ADMIN]`
  (ping, DHCP discovery, Wake-on-LAN — these fail silently without it) and
  nothing more. A USB coordinator is passed in with `devices:`.
- **`network_mode: host` for Home Assistant** (and the Matter server): mDNS,
  SSDP, Matter and Thread discovery need it.
- **Internal ports on `127.0.0.1` only.** An MQTT broker on `0.0.0.0` lets anyone
  on the WiFi — guests included — publish to `zigbee2mqtt/+/set` and drive every
  light, or open `permit_join` and pair their own devices. Zigbee2MQTT reaches
  Mosquitto over the Docker network and HA (host network) over localhost, so
  the published port is not needed on the LAN at all.
- **Zigbee2MQTT's frontend** may stay on the LAN (handy from a phone), but only
  with `frontend.auth_token` set.
- **Healthchecks on every container.** `restart: unless-stopped` only helps when
  a process dies; a healthcheck also catches "running but hung", and
  `docker compose ps` then shows it. Use
  `depends_on: condition: service_healthy` for Zigbee2MQTT → Mosquitto.
- **Docker logs capped** (3 × 10 MB per container). Without this they grow
  forever on a small SSD. Let Mosquitto log to stdout so the cap applies.

## Things that need no extra machinery

- **No watchdog cron.** `restart: unless-stopped` plus healthchecks covers it, and
  a watchdog that restarts containers fights you while debugging.
- **No nightly reboot.** See [laptop-as-server.md](laptop-as-server.md#updates-and-reboots).
- **No Node-RED.** HA's own automations are enough; logic in two places makes
  debugging twice as hard.

## Recorder

HA's own database (`home-assistant_v2.db`) is short-term history for the UI.
Keep it small: set `recorder: purge_keep_days` and exclude chatty sensors.
History you want to keep for years (energy, temperatures) goes to InfluxDB,
which is also what the backup covers. See [backup.md](backup.md).

## Day-to-day commands

```bash
sudo docker compose -f /srv/homeassistant/docker-compose.yml ps      # status and health
sudo docker compose -f /srv/homeassistant/docker-compose.yml up -d   # start / apply changes
sudo docker compose -f /srv/homeassistant/docker-compose.yml pull    # fetch newer images
sudo docker logs -f zigbee2mqtt                                       # follow one container
```

Image updates are deliberately manual (pull, then `up -d`, then check): an HA
release that breaks an integration should not land unattended at night.
