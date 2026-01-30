#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

sudo systemctl start homelab
echo "Homelab containers starting..."
sleep 5
sudo docker compose -f "$COMPOSE_FILE" ps
