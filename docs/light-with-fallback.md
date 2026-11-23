# Light with fallback

Motion-activated light with a physical button that works even when the server, network, or Zigbee2MQTT is completely down.

## Devices per room

| Device | Zigbee type | Purpose |
|---|---|---|
| Lamp | Dimmable light (e.g. IKEA KAJPLATS) | The light itself |
| Sensor | Occupancy sensor (e.g. HOBEIAN ZG-204Z) | Detects motion, triggers automation |
| Button | On/off button (e.g. IKEA RODRET or SOMRIG) | Manual override, works without server |

## Naming

The examples below use `{Room} lamp`, `{Room} button` and a Zigbee group named
`{Room}`, for readability. Any scheme works, as long as you decide it before the
first device joins: renaming later ripples through every automation. See
[zigbee.md](zigbee.md#building-the-network) for a scheme that keeps the room out
of device names.

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
| Tuya TS004F (4-button) | hold buttons 2+4 for 6s, LED 3 flashes once |
| HOBEIAN ZG-101ZD (rotary knob, reports model `TS004F`) | not documented; check `operation_mode` in its state |
| Loginovo ZG-101ZL | triple click |
| Moes ERS-10TZBVK-AA (rotary knob, reports `TS004F`) | triple click — very fast, about three clicks within one second |
| IKEA TRÅDFRI on/off | no mode — always sends real commands |

**Step 2 — create a group and put the lamp in it.** The group must be
referenced by its **friendly name**; a numeric group ID is rejected.

```
mosquitto_pub -t zigbee2mqtt/bridge/request/group/add \
  -m '{"friendly_name": "{Room}"}'
mosquitto_pub -t zigbee2mqtt/bridge/request/group/members/add \
  -m '{"group": "{Room}", "device": "{Room} lamp"}'
```

**Step 3 — connect the button to the group.** How depends on the remote — and
getting it wrong looks exactly like success, so check the table:

| Device | Connect to the group by |
|---|---|
| IKEA TRÅDFRI on/off | **bind** the button to the group |
| Tuya-family (TS004F, ZG-101ZD knob) | **adding the button itself as a group member** |

Either way the button must be awake: press it immediately before sending, and
keep pressing while retrying. A sleeping battery device is the usual reason a
request times out.

For a bind:

```
mosquitto_pub -t zigbee2mqtt/bridge/request/device/bind \
  -m '{"from": "{Room} button", "to": "{Room}", "clusters": ["genOnOff", "genLevelCtrl"]}'
```

Include `genLevelCtrl` if the button should also dim.

For group membership — the remote then sends to whichever group it belongs to:

```
mosquitto_pub -t zigbee2mqtt/bridge/request/group/members/add \
  -m '{"group": "{Room}", "device": "{Room} button"}'
```

> **How to tell which one you need.** Turn Zigbee2MQTT's log level to `debug`
> and press the button. Each `Received Zigbee message` line ends in
> `with groupID N`. **`groupID 0` means the remote is talking to the coordinator
> only** — it is not addressing any group, and no lamp will ever hear it. A bind
> that leaves it at 0 is being ignored; switch to membership. Once it shows the
> group's ID, the lamp responds. This check takes a minute and would have saved
> two evenings.

**A remote that was paired elsewhere may already target a group of its own.**
An IKEA switch that had been used before arrived bound to group 901 and ignored
everything else; adding the lamp to *that* group is what finally made it work. Check with the group
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

> **The button's parent must be the lamp, not the coordinator.** A battery
> button is an end device: it reaches the network through exactly one parent.
> Paired normally, it often picks the coordinator. If the coordinator hangs
> for hours, the button loses its parent. It keeps working for a while, then
> leaves the network, and its group membership goes with it. The fallback dies
> in exactly the outage it is meant to cover. (This happened in practice after
> a coordinator hung for a night.)
>
> Fix: stand next to the lamp and pair the button **through the lamp only**
> (in the frontend: the arrow next to *Permit join (All)*):
>
> ```
> mosquitto_pub -t zigbee2mqtt/bridge/request/permit_join \
>   -m '{"time":254,"device":"{Room} lamp"}'
> ```
>
> A button that is already paired rejoins with the same address, so its name
> stays. Re-add it to the group afterwards (`DUPLICATE_EXISTS` means it is
> already in). Then check the parent with a raw network map
> (`zigbee2mqtt/bridge/request/networkmap`, `{"type":"raw"}`): the button's
> link with `relationship: 1` must point at the lamp. A passing
> `docker stop zigbee2mqtt` test does not prove this on its own.
>
> Zigbee2MQTT's pairing guide suggests this same trick for linking a switch
> directly to a bulb, and warns it is no guarantee the router is chosen or
> kept long-term. Check the parent again after a coordinator outage.

### Layer 2: HA automation (smart behavior)

When the server is running, Home Assistant adds motion-based control:

1. **Motion detected** — lamp on at 100%
2. **60s after last motion** — dim to 50% (sensor keep_time 30s + 30s wait)
3. **90s after last motion** — lamp off (additional 30s delay)

The automation uses `mode: restart` so any new motion resets the sequence. This is a single automation instead of separate timer-based rules.

### Layer 3: HA button automations (override via MQTT)

When the server is running, the button presses are also received via MQTT. Two simple automations handle this:

- **Button on**: turns lamp on at 100%
- **Button off**: turns lamp off

These coexist with the direct Zigbee bind. The bind handles the radio-level toggle; the HA automations ensure the state is tracked and can trigger additional logic if needed.

## Adding a new room

1. **Add devices to Zigbee2MQTT** and name them `{Room} lamp`, `{Room} sensor`, `{Room} button`
2. **Create a Zigbee group** named `{Room}` containing the lamp — mandatory,
   not optional; the bind goes to this group and not to the lamp
3. **Put the button in `command` mode** and **connect it to the group** —
   bind or membership depending on the model (Layer 1); confirm with the
   `groupID` check
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

**A mode switch that a triple click triggers can be hit by accident.** Someone
pressing impatiently a few times flips the remote back to `event` mode, and the
fallback is gone without anything looking wrong — Zigbee2MQTT still receives
every press. So when a button stops working, check `operation_mode` first, and
give such a remote an automation that notifies when its
`select.*_operation_mode` turns `event`, with the fix in the message (example in
[`examples/homeassistant/monitoring-automations.yaml`](../examples/homeassistant/monitoring-automations.yaml)).

**A rotary knob is a poor toilet button.** A knob turns slightly when pressed and
then sends a brightness or colour-temperature step instead of `toggle`; a lamp
that is off ignores those. For fallback buttons prefer a plain push button
(IKEA RODRET, BILRESA) over a knob. If you already have a knob, an HA
automation can cover it while the server runs: after a step that is not followed
by a `toggle` within 2 s, turn the lamp on.

**Bulbs that reject `onLevel`.** Some bulbs (Philips Hue among them) ignore the
Zigbee `onLevel` attribute, so a bound button switches them on at their last
brightness. HA can correct that while it runs: an automation on the lamp going
off → on with a context that has no `user_id` and no `parent_id` (i.e. not
caused by HA) sets it to 100 %.

**HA's state for a bound lamp can be wrong.** Changes made through a group bind
do not always reach HA. Do not build automations that rely on the lamp's
reported state being exact.

## Design principle

Important lights (toilets, hallways, stairs) must always have a physical fallback via direct Zigbee binding. Smart behavior is a bonus layer, not a dependency.
