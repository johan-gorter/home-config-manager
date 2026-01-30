#!/bin/bash
sudo systemctl start homelab
echo "Homelab containers starting..."
sleep 5
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$(dirname "$SCRIPT_DIR")/config/docker-compose.yml"
sudo docker compose -f "$COMPOSE_FILE" ps
