# Light with fallback

Motion-activated light with a physical button that works even when the server, network, or Zigbee2MQTT is completely down.

## Devices per room

| Device | Zigbee type | Purpose |
|---|---|---|
| Lamp | Dimmable light (e.g. IKEA KAJPLATS) | The light itself |
| Sensor | Occupancy sensor (e.g. HOBEIAN ZG-204Z) | Detects motion, triggers automation |
| Knop | On/off button (e.g. IKEA SOMRIG E2489) | Manual override, works without server |

## Naming convention

All devices follow the pattern: **`{Room} {device}`**

| Item | Pattern | Example |
|---|---|---|
| Zigbee device | `{Room} lamp` / `sensor` / `knop` | `Toilet beneden lamp` |
| Zigbee group | `{Room}` | `Toilet beneden` |
| HA entity | `light.{room_slug}_lamp` | `light.toilet_beneden_lamp` |
| HA entity | `binary_sensor.{room_slug}_sensor_occupancy` | `binary_sensor.toilet_beneden_sensor_occupancy` |
| Automation ID | `{room_slug}_lamp_control` | `toilet_beneden_lamp_control` |
| Automation ID | `{room_slug}_knop_on` / `_off` | `toilet_beneden_knop_on` |
| Automation alias | `{Room}: Lamp control` | `Toilet beneden: Lamp control` |
| Automation alias | `{Room}: Knop aan` / `uit` | `Toilet beneden: Knop aan` |

The `{room_slug}` is the lowercase, underscore-separated version of `{Room}`.

## How it works

### Layer 1: Direct Zigbee bind (always works)

The button controls the lamp through a Zigbee **group**. This operates at the
radio level — no coordinator, no MQTT, no Home Assistant needed. If everything
is down, the button still works. Zigbee2MQTT's own documentation is explicit
that binding "works even when home automation software, Zigbee2MQTT, or the
coordinator is down".

> **Bind to a group, not to the lamp.** This is the single thing that wastes the
> most time. Most of these remotes can drive exactly one group and cannot drive
> an individual device. A device-level bind reports `Successfully bound` and
> then does nothing at all — there is no error to go on. Verified on a Tuya
> TS004F, a Loginovo ZG-101ZL and an IKEA TRÅDFRI on/off switch; the
> Zigbee2MQTT docs state it outright for the TS004F:
> *"Directly controlling individual devices is not supported. Binding/unbinding
> appears successful, but it's not effective."*

**Step 1 — put the remote in `command` mode.** In `event` mode a remote sends
non-standard Zigbee messages that only the coordinator understands, so a bind
can never work. `command` mode sends real Zigbee commands.

Writing `operation_mode` over MQTT often fails with `UNSUPPORTED_ATTRIBUTE`
even on devices that support the mode. **Every one of these remotes also has a
physical gesture**, and that one does work:

| Device | Switch to command mode |
|---|---|
| Tuya TS004F | hold buttons 2+4 for 6s, LED 3 flashes once |
| Loginovo ZG-101ZL | triple click |
| IKEA TRÅDFRI on/off | no mode — always sends real commands |

**Step 2 — create a group and put the lamp in it.** The group must be
referenced by its **friendly name**; a numeric group ID is rejected.

```
mosquitto_pub -t zigbee2mqtt/bridge/request/group/add \
  -m '{"friendly_name": "{Room}"}'
mosquitto_pub -t zigbee2mqtt/bridge/request/group/members/add \
  -m '{"group": "{Room}", "device": "{Room} lamp"}'
```

**Step 3 — bind the button to the group.** The button must be awake: press it
immediately before sending, and keep pressing while retrying. A sleeping
battery device is the usual reason a bind times out.

```
mosquitto_pub -t zigbee2mqtt/bridge/request/device/bind \
  -m '{"from": "{Room} knop", "to": "{Room}", "clusters": ["genOnOff", "genLevelCtrl"]}'
```

Include `genLevelCtrl` if the button should also dim.

**A remote that was paired elsewhere may already target a group of its own.**
The IKEA switch arrived bound to group 901 and ignored everything else; adding
the lamp to *that* group is what finally made it work. Check with the group
list before assuming a new group is needed.

### Verifying it actually works

The only test that counts is with the software gone:

```
docker stop zigbee2mqtt
```

Then press the button. Set the lamp to a known state first — if the lamp is
already on, an `on` command looks identical to nothing happening, which is its
own afternoon of confusion.

Note that with Zigbee2MQTT stopped the coordinator leaves the network too, so
the message can no longer be relayed through it. Button and lamp must be in
direct radio range, or have a mains-powered router between them that stays up.
A fallback button therefore belongs in the same room as its lamp.

### Layer 2: HA automation (smart behavior)

When the server is running, Home Assistant adds motion-based control:

1. **Motion detected** — lamp on at 100%
2. **60s after last motion** — dim to 50% (sensor keep_time 30s + 30s wait)
3. **90s after last motion** — lamp off (additional 30s delay)

The automation uses `mode: restart` so any new motion resets the sequence. This is a single automation instead of separate timer-based rules.

### Layer 3: HA button automations (override via MQTT)

When the server is running, the button presses are also received via MQTT. Two simple automations handle this:

- **Knop aan**: turns lamp on at 100%
- **Knop uit**: turns lamp off

These coexist with the direct Zigbee bind. The bind handles the radio-level toggle; the HA automations ensure the state is tracked and can trigger additional logic if needed.

## Adding a new room

1. **Add devices to Zigbee2MQTT** and name them `{Room} lamp`, `{Room} sensor`, `{Room} knop`
2. **Create a Zigbee group** named `{Room}` containing the lamp — mandatory,
   not optional; the bind goes to this group and not to the lamp
3. **Put the button in `command` mode** and **bind it to the group** (Layer 1)
4. **Copy the automations** from an existing room, replacing the room name and entity IDs
5. **Adjust timings** if needed (the dim/off delays in the automation)

## Choosing hardware

A battery button is not the most robust option. For spaces where reliability
really matters, a **mains-powered Zigbee switch module behind the existing wall
switch, driving a dumb lamp**, is stronger: the wall switch sits physically in
the circuit, so it works with no Zigbee, no coordinator, no server and no
battery. It is also a router rather than an end device, so it cannot be dropped
from the network.

That also explains why a smart bulb plus a hard wall switch is a bad pairing:
whoever flips the switch cuts power to the bulb and there is nothing left to
control.

Watch the battery on button-based fallbacks. A dying CR2032 drops transmit
power, the device misses its polls, and its parent evicts it from the child
table — which presents as a remote that works for weeks and then silently stops.
If a button "falls off the network every month", suspect the battery and the
parent router before blaming the model.

## Design principle

Important lights (toilets, hallways, stairs) must always have a physical fallback via direct Zigbee binding. Smart behavior is a bonus layer, not a dependency.
