#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

echo "=== Services ==="
printf "  homelab: "; systemctl is-active homelab.service 2>/dev/null || echo "inactive"
printf "  kiosk:   "; systemctl is-active kiosk.service 2>/dev/null || echo "inactive"
echo
echo "=== Containers ==="
sudo docker compose -f "$COMPOSE_FILE" ps
