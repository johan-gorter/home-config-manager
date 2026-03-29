#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

echo "=== Services ==="
printf "  homelab: "; systemctl is-active homelab.service 2>/dev/null || echo "inactive"
printf "  kiosk:   "; systemctl is-active kiosk.service 2>/dev/null || echo "inactive"
echo
echo "=== Containers ==="
sudo docker compose -f "$COMPOSE_FILE" ps
echo
echo "=== Zigbee Binds ==="
DEVICES_JSON=$(sudo docker exec mosquitto mosquitto_sub -t 'zigbee2mqtt/bridge/devices' -C 1 -W 5 2>/dev/null) || true
if [ -z "$DEVICES_JSON" ]; then
  echo "  unavailable"
else
  echo "$DEVICES_JSON" | python3 -c '
import json, sys
devices = json.load(sys.stdin)
coordinator = next((d["ieee_address"] for d in devices if d.get("type") == "Coordinator"), None)
lookup = {d["ieee_address"]: d["friendly_name"] for d in devices if "ieee_address" in d}
found = False
for dev in devices:
    name = dev.get("friendly_name", "unknown")
    for ep in dev.get("endpoints", {}).values():
        for bind in ep.get("bindings", []):
            cluster = bind.get("cluster", "")
            if cluster in ("genPollCtrl", "genPowerCfg"):
                continue
            target = bind.get("target", {})
            if target.get("type") == "endpoint":
                if target.get("ieee_address") == coordinator:
                    continue
                target_name = lookup.get(target.get("ieee_address", ""), target.get("ieee_address", "?"))
            elif target.get("type") == "group":
                target_name = "group " + str(target.get("id", "?"))
            else:
                continue
            print(f"  {name} -> {target_name} ({cluster})")
            found = True
if not found:
    print("  no binds found")
' 2>/dev/null || echo "  unavailable"
fi
