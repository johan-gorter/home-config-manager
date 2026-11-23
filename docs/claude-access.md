# Claude's access to Home Assistant

Claude Code runs on the server itself and manages HA through its APIs, the same
way the web interface does.

## Ground rules

- **Devices and integrations are added through the UI or API, never in files.**
  `.storage/` is HA's internal state; hand-editing it corrupts HA in ways that
  show up much later. File access is for YAML only: automations, scripts,
  templates, custom components.
- Automations created through the API land in `automations.yaml`; snapshot them
  into the house repo afterwards (see [backup.md](backup.md#git-for-the-yaml)).
- Never paste a token into a chat or commit it. If that happens, revoke it
  (profile → Security) and make a new one.

## Token

The HA owner creates a long-lived access token (profile → Security →
Long-lived access tokens) and stores it in a file only the admin can read:

```bash
install -D -m 600 /dev/null ~/.config/homeassistant/token
nano ~/.config/homeassistant/token      # paste the token, nothing else
```

## MCP — everyday control

Enable HA's **Model Context Protocol Server** integration. It offers the Assist
tools (turn on/off, set lights, live state) for entities exposed to Assist.

Register it in Claude Code with a `headersHelper`, so the token stays out of
Claude's config file. `~/.config/homeassistant/mcp-headers.sh` (mode 700):

```sh
#!/bin/sh
printf '{"Authorization": "Bearer %s"}\n' "$(cat "$HOME/.config/homeassistant/token")"
```

and in `~/.claude.json` under `mcpServers`:

```json
"homeassistant": {
  "type": "http",
  "url": "http://localhost:8123/api/mcp",
  "headersHelper": "/home/<admin>/.config/homeassistant/mcp-headers.sh"
}
```

## REST and WebSocket — administration

For what MCP cannot do (integrations, areas, the device registry, HTTP
settings):

```bash
curl -s -H "Authorization: Bearer $(cat ~/.config/homeassistant/token)" \
  http://localhost:8123/api/states | head
```

Much of HA's administration is WebSocket-only (`config/area_registry/*`,
`config/device_registry/*`, `http/config/*`, `otbr/*`). The easiest way to call
it is a short Python script run inside the HA container, where `aiohttp` is
available:

```bash
sudo docker exec -i -e HA_TOKEN="$(cat ~/.config/homeassistant/token)" homeassistant python3 - <<'EOF'
import asyncio, aiohttp, json, os
TOKEN = os.environ['HA_TOKEN']
async def main():
    async with aiohttp.ClientSession() as s, s.ws_connect('http://localhost:8123/api/websocket') as ws:
        await ws.receive_json()
        await ws.send_json({'type': 'auth', 'access_token': TOKEN}); await ws.receive_json()
        await ws.send_json({'id': 1, 'type': 'config/area_registry/list'})
        print(json.dumps(await ws.receive_json(), indent=1))
asyncio.run(main())
EOF
```

## Zigbee2MQTT

Through MQTT on the bridge topics, from inside the Mosquitto container:

```bash
sudo docker exec mosquitto mosquitto_pub -t zigbee2mqtt/bridge/request/devices/get -m ''
sudo docker exec mosquitto mosquitto_sub -t 'zigbee2mqtt/bridge/response/#' -C 1 -W 10
```
