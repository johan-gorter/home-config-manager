#!/bin/bash
echo "=== Services ==="
printf "  homelab: "; systemctl is-active homelab.service 2>/dev/null || echo "inactive"
printf "  kiosk:   "; systemctl is-active kiosk.service 2>/dev/null || echo "inactive"
echo
echo "=== Containers ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$(dirname "$SCRIPT_DIR")/config/docker-compose.yml"
sudo docker compose -f "$COMPOSE_FILE" ps
