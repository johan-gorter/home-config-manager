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

Running: Home Assistant 2026.10.0, Mosquitto 2, Zigbee2MQTT 2.14.2.

**First device paired on 2026-10-09**: a Philips Hue white filament globe
G125 B22 (LWO007 / 9290030521), IEEE `0x001788010f2617ff`. It joined and
interviewed cleanly and reports **LQI 108** — a sound direct link to the
coordinator despite the distance, with margin to spare. It is a *Router*, being
mains-powered, so it extends the mesh rather than depending on it. Brightness
was set successfully from the Zigbee2MQTT frontend, which was the goal of these
sessions.

It still carries its IEEE address as a friendly name and needs renaming to
`{Room} lamp` per the convention in `light-with-fallback.md`.

Home Assistant onboarding is still not done (no account), so the MQTT
integration is not configured either — the lamp is driven from Zigbee2MQTT
directly.

Not built, by agreement: kiosk, backups, InfluxDB, Tailscale. See `ROADMAP.md`.

## 2026-10-11 — three more devices, and the binding lesson

Paired and named: `ledstrip-wellness-1` (DOMRAEM RGBWC, router),
`draaiknop-1` (Tuya TS004F), `knop-1` (Loginovo ZG-101ZL) and `knop-2`
(IKEA TRÅDFRI on/off switch).

Most of the evening went into making a button control the lamp with the server
down — Layer 1 of `light-with-fallback.md`. Three wrong turns, recorded so
nobody repeats them:

1. **Device-level binds report success and do nothing.** `genOnOff` and
   `genLevelCtrl` were bound from each button straight to `globe-lamp-1`
   endpoint 11, Zigbee2MQTT logged `Successfully bound`, and nothing ever
   happened. These remotes drive exactly one *group*; individual devices are
   not supported. The Zigbee2MQTT docs say so plainly for the TS004F.
2. **`operation_mode` cannot always be written over MQTT.** Both Tuya-family
   buttons returned `UNSUPPORTED_ATTRIBUTE`, 40 attempts at link quality 228.
   That was read as "this hardware cannot do it" and the user was told to buy
   different buttons — **wrong**. Both have a physical gesture that does the
   same job: buttons 2+4 for 6s on the TS004F, a triple click on the ZG-101ZL.
3. **A group must be addressed by friendly name.** `{"group":"901"}` was
   rejected with `Group '901' does not exist` even though group 901 was right
   there in the database.

What finally worked: the IKEA switch had arrived already bound to **group 901**
from a previous life. Creating a Zigbee2MQTT group with that ID and a friendly
name, then adding `globe-lamp-1` to it, made the button work immediately —
including with the `zigbee2mqtt` container stopped, which is the only test that
counts.

Groups now defined: `groep-globe-1` (id 1) and `groep-901` (id 901), both
containing `globe-lamp-1`.

Leftover: the ineffective device-level binds on all three buttons are still in
place. Harmless, but misleading — they suggest a working fallback where there
is none. Worth clearing with `bridge/request/device/binds/clear`.

## 2026-10-13 — lamp-tradfri-1 on the knob

Paired `lamp-tradfri-1`: IKEA TRÅDFRI LED1623G12 (E27, opal, 1000 lm), IEEE
`0x000b57fffe2f06f4`, router. It is **fixed warm white** — no
`lightingColorCtrl` cluster, so there is no colour temperature to set; the
request for "warmest possible" is simply what it does. LQI 36 at first contact.

Goal: `draaiknop-1` drives it directly, on/off and dimming. Correction to the
2026-10-11 entry: Zigbee2MQTT identifies `draaiknop-1` as a **HOBEIAN ZG-101ZD
smart knob**; it only reports `TS004F` as its model ID. Its state already read
`operation_mode: command` this time.

1. Created `groep-tradfri-1` (id 2) with the lamp; a command to the group
   reached the lamp.
2. Bound the knob to the group (`genOnOff`, `genLevelCtrl`) and removed its old,
   never-working device binds to `globe-lamp-1`. Zigbee2MQTT logged
   `Successfully bound`. **The lamp did nothing.**
3. Debug logging showed why: every message from the knob carried **`groupID 0`**
   — addressed to the coordinator, ignoring its binding table entirely.
4. Added the **knob itself** as a member of `groep-tradfri-1`. From the next
   press on, its messages carried `groupID 2` and the lamp switched and dimmed.

So the two remote families need different treatment: the IKEA switch follows a
group **bind**, the Tuya-family knob follows group **membership**. Both are now
in `light-with-fallback.md`, with the `groupID` log check as the way to tell.

Verified working with Zigbee2MQTT running. **Not yet re-tested with the
container stopped**, which is the test that counts for a fallback.

Groups now: `groep-globe-1` (1) and `groep-901` (901) with `globe-lamp-1`,
unchanged, so `knop-2` keeps controlling the globe; `groep-tradfri-1` (2) with
`lamp-tradfri-1` and `draaiknop-1`. The knob's bind to group 2 is still there;
harmless and ineffective.

Also noticed: `ledstrip-wellness-1` (`0xa4c13833e9926b53`) is still named in
`configuration.yaml` but no longer in Zigbee2MQTT's device database.

## Open items created by these sessions

- Zigbee2MQTT's frontend listens on `0.0.0.0:8080` with no authentication.
- The Deco mesh should be pinned to a fixed 2.4 GHz channel; automatic selection
  can drift onto channel 11, which sits right against Zigbee channel 25.
- `coordinator_backup.json` now holds the network key and exists on one SSD only.
- Bluetooth fails in Home Assistant — the container has no access to the host
  D-Bus. Needs a D-Bus mount if Bluetooth devices are wanted.
