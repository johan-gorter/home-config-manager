# Zigbee

## Choosing a coordinator

| | Network coordinator (Ethernet/PoE) | USB stick |
|---|---|---|
| Placement | Anywhere central in the house, away from the server | On a USB extension cable |
| Device name | `tcp://<ip>:6638` — stable with a DHCP reservation | Needs a udev rule (below) |
| Failure mode | Can hang; first aid is a power cycle | Device name can change after a reboot |

A network coordinator (for example an SMLIGHT SLZB model) is the more flexible
choice: the server can sit wherever it is convenient, and some models carry a
second radio for Thread. Some have a USB-C port that is **only for power and a
service console**, not for Zigbee — check before planning on it.

Set `serial.adapter` to match the chipset: `ember` for Silicon Labs EFR32,
`zstack` for TI CC26xx. See
[`examples/zigbee2mqtt-configuration.yaml`](../examples/zigbee2mqtt-configuration.yaml).

### USB: stable name and an extension cable

`/dev/ttyUSB0` depends on enumeration order. If it moves, Zigbee2MQTT does not
start and **no light works**. Give the stick a fixed name with a udev rule
([`examples/99-zigbee.rules`](../examples/99-zigbee.rules)) and use `/dev/zigbee`
everywhere. Match on serial number; cheap CH340-based sticks often lack a unique
one, then match on the USB port path.

Put the stick on a **USB extension cable**, away from the computer. USB 3 ports
and SSDs radiate across the 2.4 GHz band; a stick plugged straight into a laptop
loses most of its range, and a better antenna does not make up for it.

## Channel

Zigbee and 2.4 GHz WiFi share the band. **Choose the channel before anything
joins** — changing it later means re-pairing every device.

1. Look at which 2.4 GHz WiFi channels are in use, yours and the neighbours'
   (a WiFi analyser app on a phone).
2. **Pin your own access points to fixed 2.4 GHz channels** (1, 6 or 11).
   Mesh systems choose automatically by default; an access point that drifts
   next to your Zigbee channel shows up as random, unexplained Zigbee dropouts
   across the whole house.
3. Pick the Zigbee channel furthest from all of them. 15, 20 and 25 avoid WiFi
   channels 1, 6 and 11; 25 is right above channel 11, so keep WiFi off 11 if
   you choose 25.

Keep as many WiFi devices as possible on 5 GHz.

## Building the network

- **Routers first, battery devices afterwards.** Only mains-powered devices
  (fixed lamps, plugs, switch modules) route; battery sensors and buttons do not.
  A device picks its parent when it joins, so a sensor that joins before the
  routers are in place ends up on the coordinator from a bad spot, and stays
  there.
- **Pair devices at their final location**, not next to the server.
- **A few reliable routers beat many cheap ones.** Some cheap plugs route badly
  and drop their children.
- **Prefer Zigbee for multiprotocol devices** (Zigbee + Bluetooth + Matter):
  only Zigbee allows the direct button-to-lamp bind of
  [light-with-fallback.md](light-with-fallback.md).
- **Name devices before using them** in automations. A scheme that works well:
  lowercase, device type plus a number (`lamp-3`, `button-2`, `sensor-motion-1`),
  with the room as the HA **area** rather than part of the name. Devices move
  between rooms; names that contain the room then lie.

## Back up `coordinator_backup.json` immediately

Zigbee2MQTT writes `coordinator_backup.json` with the network key and device
table. Lose it after a coordinator failure and you re-pair every device in the
house and redo every bind. It is the most valuable file of the whole setup. See
[backup.md](backup.md).

## When the coordinator hangs

Network coordinators can hang: no ping, no web UI, Zigbee2MQTT restarting in a
loop. HA itself keeps running and Zigbee2MQTT resumes by itself once the
coordinator is back. **First aid: unplug its power for 10 seconds.** If it
recurs, update its firmware, then suspect the power supply (use a good 5 V ≥ 2 A
adapter or PoE) and the network cable/port.

Make sure you hear about it: a monitoring automation on
`binary_sensor.zigbee2mqtt_bridge_connection_state` that notifies your phone
after 5 minutes offline
([`examples/homeassistant/monitoring-automations.yaml`](../examples/homeassistant/monitoring-automations.yaml)).
It cannot report HA itself being down — that needs an outside check.

Lights on direct binds keep working during such an outage, **provided the
buttons' parent is not the coordinator** — see
[light-with-fallback.md](light-with-fallback.md#verifying-it-actually-works).

## Firmware and web UIs

The web UI of many network coordinators has **no login**: anyone on the LAN can
change radio modes or flash firmware. Keep guests on a separate network if that
matters to you. When a vendor integration exists in HA (e.g. SMLIGHT), firmware
can be updated from HA — but never update a radio blindly when a specific
firmware version was chosen for a reason; write that reason down in the house repo.
