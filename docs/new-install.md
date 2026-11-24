# New installation — checklist

The order matters. Each step links to the document with the details and the
reasoning. Record what you actually did, with dates, in the private repo of the
house (see the end of this page): six months later that log is worth more than
any script.

## 0. Decide before you start

- [ ] **Hardware.** An old laptop is a good server: low power, built-in screen
      for a kiosk, and the battery is a free UPS. Wired Ethernet is nicer, but
      WiFi works. See [laptop-as-server.md](laptop-as-server.md).
- [ ] **Zigbee coordinator.** Prefer a network (Ethernet) coordinator, or a USB
      stick on an extension cable. See [zigbee.md](zigbee.md).
- [ ] **The WiFi channels in the house.** Needed before choosing the Zigbee
      channel, which cannot be changed later without re-pairing everything.
- [ ] **Which rooms are essential** (toilets, hallways, stairs). Those lights get
      a physical fallback. See [light-with-fallback.md](light-with-fallback.md).
- [ ] **Naming scheme** for devices. Decide before the first device joins;
      renaming later ripples through every automation.

## 1. Base system

- [ ] Ubuntu (Desktop if you want a kiosk, Server otherwise), latest LTS.
- [ ] DHCP reservation for the server (and for a network coordinator) in the
      router. Integrations break when IP addresses move.
- [ ] Hostname and mDNS (`avahi-daemon`, usually already present on Desktop), so
      the server is reachable as `<hostname>.local`.
- [ ] Sleep and lid switch off, battery charge limit, unattended upgrades with
      reboot-when-needed. See [laptop-as-server.md](laptop-as-server.md).
- [ ] Users, groups and the data directory `/srv/homeassistant`. See
      [users-and-permissions.md](users-and-permissions.md).

## 2. The stack

- [ ] Docker from Ubuntu's own packages: `apt install docker.io docker-compose-v2`.
- [ ] `docker-compose.yml`, Mosquitto and Zigbee2MQTT config from
      [`examples/`](../examples/), adapted. See [architecture.md](architecture.md).
- [ ] `homelab.service`, so the stack comes back after every reboot. Test it:
      reboot and check that everything is `healthy` without touching anything.
- [ ] **Onboard Home Assistant immediately.** Until onboarding is done, anyone
      on the network can claim the owner account at `:8123`.
- [ ] **Check the home location** (Settings → System → General), including the
      elevation. If onboarding skipped it, or it was done through the API, it
      quietly stays on Home Assistant's default (central Amsterdam, 0 m). That
      default is wrong for sunrise and sunset automations and for every weather
      integration, which picks its forecast point or nearest weather station
      from it. Fix it before adding weather.

## 3. Zigbee

- [ ] Choose the channel, then start Zigbee2MQTT. See [zigbee.md](zigbee.md).
- [ ] Back up `coordinator_backup.json` right away — it holds the network key.
- [ ] Pair **mains-powered devices first** (routers), at their final location;
      battery devices afterwards.
- [ ] Fallback buttons for essential lights, verified with Zigbee2MQTT stopped.
- [ ] Monitoring automation for "Zigbee2MQTT offline"
      ([`examples/homeassistant/monitoring-automations.yaml`](../examples/homeassistant/monitoring-automations.yaml)).

## 4. Integrations and Claude

- [ ] MQTT integration in HA (broker `127.0.0.1`).
- [ ] Optional: InfluxDB for long-term history, Matter/Thread. See
      [thread-matter.md](thread-matter.md).
- [ ] Token and MCP access for Claude. See [claude-access.md](claude-access.md).

## 5. Kiosk (optional)

- [ ] See [kiosk.md](kiosk.md). Create the non-admin HA user for it first.

## 6. Backup and remote access

- [ ] Backup, and a **restore test**. See [backup.md](backup.md).
- [ ] Remote access, MFA on for every account. See
      [remote-access.md](remote-access.md).

## A private repo for your house

Keep a private git repository per house with:

- `CLAUDE.md` — the actual state: hostname, IPs, coordinator, users, which
  device is where, automations and why, known issues. Claude reads this every
  session, so keep it current.
- `ROADMAP.md` — what is decided, what is still open.
- `docs/install-log.md` — what was done, when, and what went wrong.
- `config/` — a snapshot of the hand-editable YAML (see [backup.md](backup.md#git-for-the-yaml)).

Private, because automations, schedules and presence sensors reveal when nobody
is home.

Link it from this repo with a git-ignored `CLAUDE.local.md` (see
[CLAUDE.md](../CLAUDE.md)), so Claude knows which house it is working on.
