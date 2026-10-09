# Install log — October 2026

What was actually done on the Geulwijk machine, by hand, in session order. This
exists so the next person (or the next Claude session) can tell the difference
between what the repo's `scripts/` *claim* and what the machine *is*.

The goal of these sessions was narrow: get far enough to pair one lamp and change
its brightness. Everything not needed for that was deliberately skipped.

## 2026-10-07 — base install

**Tooling.** `git` and `gh` were missing on the fresh Ubuntu install; both were
installed. Note that `scripts/config-backup.sh` depends on `git` and, combined
with `set -euo pipefail` and the `&&` chain in its cron line, would have failed
silently and taken `maintenance.sh` down with it.

**Docker.** Installed from **Ubuntu's own packages** (`docker.io` 29.1.3,
`docker-compose-v2` 2.40.3) rather than Docker's upstream repository as
`scripts/lib/docker.sh` does. One fewer third-party repo and signing key, and
security updates arrive through the normal channel. `acl` installed as well.

**Users and permissions.** Created group and system user `homeassistant`
(uid 997, nologin); added `jgo` to the group. Created `/srv/homeassistant` —
deliberately *outside* the git repository, unlike the old `scripts/` which put
data in `config/` inside the checkout.

Permissions are `root:homeassistant`, mode 750, setgid on every directory, plus a
default ACL `g:homeassistant:rwX`. Extra ACLs for uid 1883 on Mosquitto's `data`
and `log` directories, because that container drops privileges.

This replaces the old `chown -R root:root` + `chmod -R 755`, which made
`.storage/core.config_entries` and `secrets.yaml` — all integration passwords in
plain text — world-readable.

**Hardening applied from the start**, rather than retrofitted:
- Mosquitto published on `127.0.0.1:1883` instead of `0.0.0.0`. Zigbee2MQTT
  reaches it over the Docker bridge by service name; Home Assistant reaches it
  over localhost because it uses host networking. Nothing is lost.
- Home Assistant runs **without** `privileged: true` — only
  `cap_add: [NET_RAW, NET_ADMIN]`, which is what `ping`, `wake_on_lan` and
  DHCP discovery actually need.

**Power.** Masked `sleep.target`, `suspend.target`, `hibernate.target` and
`hybrid-sleep.target`; logind set to ignore the lid switch on all power sources.
Without this the "server" suspends the moment the lid closes.

**Autostart.** `homelab.service` (oneshot, `RemainAfterExit`), enabled.

**Zigbee adapter, first attempt.** The adapter enumerated as an Espressif
ESP32-S3 (`303a:1001`, serial `50:78:7D:D7:E3:B0`) on `/dev/ttyACM0` — not the
CH340/CC2652 the old config assumed. A udev rule was written matching that serial
to a stable `/dev/zigbee` symlink, and Zigbee2MQTT was configured with
`adapter: ember` (Silicon Labs), not `zstack`.

It did not work: the ASH layer reset in a loop. Zigbee2MQTT was stopped.

**Channel choice.** A WiFi survey showed the house network `gorterm` on 2.4 GHz
channel 8, with neighbours on 2, 4 and 7 — the lower half of the band is
crowded. **Zigbee channel 25** was chosen for clearance. This is effectively a
one-time decision: changing it after devices join means re-pairing all of them.

## 2026-10-09 — coordinator on the network

**Reboot verified.** The user ran a full `apt upgrade` and rebooted (kernel
7.0.0-31 → 7.0.0-38). Home Assistant and Mosquitto came back automatically.
Zigbee2MQTT stayed down, correctly — `restart: unless-stopped` honours a manual
stop.

**The adapter was identified as a SMLIGHT SLZB-MR5U**: ESP32-S3 core running
SLZB-OS, two EFR32MG24 radios, Ethernet-first with PoE or USB-C power.

**USB-C was ruled out as a Zigbee transport, empirically.** Probing the serial
port found a text console:

```
-SM Console-
wipe | test_mode | device_ip | otbr_init | otbr_deinit
```

The decisive evidence: the console had answered Zigbee2MQTT's earlier EZSP/ASH
reset frames with `Unknown cmd: <\x1a\xc08\xbc~...>`. A text parser sits behind
that port, not a radio. `device_ip` reported `IP: have no ip`. There is no
console command to expose the radio over USB and none to configure WiFi.

So on this model USB-C is power plus console only — unlike the SLZB-07, which is
a genuine USB stick.

**Found on the LAN.** Once the user connected it to wired Ethernet with USB-C
power, an ARP sweep found it at **192.168.68.109**, MAC `52:78:7D:D7:E3:B0` —
the USB serial's base MAC with the locally-administered bit set, which is how an
ESP32 derives its Ethernet MAC. Port 80 (web UI) and **6638** (Zigbee socket)
were open.

**Switched to TCP.** Zigbee2MQTT reconfigured to
`port: tcp://192.168.68.109:6638`, and the now-meaningless `devices:` and
`/run/udev` mappings removed from the compose file — the container would not
have started with a `/dev/zigbee` that no longer exists.

It connected: EmberZNet 7.4.2 [GA], EZSP 13. A new network was formed on
**channel 25, PAN ID 0x1a62 (6754)**, and `coordinator_backup.json` was written.

**DHCP reservations** for both the laptop and the coordinator were set by the
user in the TP-Link Deco mesh.

## State at the end

Running: Home Assistant 2026.10.0, Mosquitto 2, Zigbee2MQTT 2.14.2. Zero devices
paired. Home Assistant onboarding not yet done (no account), so the MQTT
integration is not configured either.

Not built, by agreement: kiosk, backups, InfluxDB, Tailscale. See `ROADMAP.md`.

## Open items created by these sessions

- Zigbee2MQTT's frontend listens on `0.0.0.0:8080` with no authentication.
- The Deco mesh should be pinned to a fixed 2.4 GHz channel; automatic selection
  can drift onto channel 11, which sits right against Zigbee channel 25.
- `coordinator_backup.json` now holds the network key and exists on one SSD only.
- Hostname is `sticker`, but the user calls the machine *silver*.
- Bluetooth fails in Home Assistant — the container has no access to the host
  D-Bus. Needs a D-Bus mount if Bluetooth devices are wanted.
