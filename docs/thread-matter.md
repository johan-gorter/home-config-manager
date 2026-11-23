# Thread and Matter

Optional. Zigbee covers most devices; add Thread/Matter when a device only
speaks Matter, or a sensor works noticeably better that way.

## Pieces

| Piece | Where |
|---|---|
| Matter controller | `matter-server` container, `127.0.0.1:5580` (see [`examples/docker-compose.yml`](../examples/docker-compose.yml)) |
| Thread border router (OTBR) | On a coordinator with a second radio (some SMLIGHT models run OTBR on the device itself), or a separate dongle |
| HA integrations | **Matter** (`ws://localhost:5580/ws`), **Open Thread Border Router**, **Thread** |

Use the maintained Matter server image (`ghcr.io/matter-js/matterjs-server`);
the older `python-matter-server` stopped being updated in 2025.

## Rules

- **Never keep a factory Thread dataset.** Some border routers start with a
  default network that uses a public, well-known network key (`00112233…eeff`).
  HA flags it as insecure. Create a new network with a random key from HA
  (WebSocket `otbr/create_network`) **before** anything joins, and make it HA's
  preferred dataset.
- **Choose the Thread channel** the same way as the Zigbee channel (see
  [zigbee.md](zigbee.md#channel)), and keep it apart from Zigbee. Unlike Zigbee,
  a Thread channel change needs no re-pairing.
- **IPv6 usually needs nothing extra.** NetworkManager installs the route to the
  Thread prefix from the border router's advertisements.
- **Prefer Zigbee for devices that do both.** Zigbee allows direct binds (see
  [light-with-fallback.md](light-with-fallback.md)) and often gives longer
  battery life. Some devices ship in Thread mode and ignore Zigbee permit-join
  until switched with the vendor's app.

## Pairing a Matter device

With the HA Companion app on an Android phone:

1. *Settings → Companion app → Troubleshooting → Sync Thread credentials.*
2. *Settings → Devices → Add device → Add Matter device.*

If the phone hangs on "checking the connection with Thread network …" and names
an **old** network, it still holds stale credentials. Check HA's preferred
dataset, then sync again.

## Back up the fabric

The Matter server's data directory holds the fabric keys. Lose it and every
Matter device must be reset and re-paired. Include it in the backup.
