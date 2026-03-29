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

The button is bound directly to the lamp using a `genOnOff` cluster bind. This operates at the Zigbee radio level — no coordinator, no MQTT, no Home Assistant needed. If everything is down, the button still toggles the lamp.

Create the bind (button must be awake — press it right before):

```
mosquitto_pub -t zigbee2mqtt/bridge/request/device/bind \
  -m '{"from": "{Room} knop", "to": "{Room} lamp", "clusters": ["genOnOff"]}'
```

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
2. **Create a Zigbee group** named `{Room}` containing the lamp
3. **Create the direct bind** from knop to lamp (see Layer 1 above)
4. **Copy the automations** from an existing room, replacing the room name and entity IDs
5. **Adjust timings** if needed (the dim/off delays in the automation)

## Design principle

Important lights (toilets, hallways, stairs) must always have a physical fallback via direct Zigbee binding. Smart behavior is a bonus layer, not a dependency.
