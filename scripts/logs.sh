#!/bin/bash
# Usage: ./logs.sh [service]
# Examples:
#   ./logs.sh              # all containers
#   ./logs.sh homeassistant
#   ./logs.sh mosquitto
#   ./logs.sh zigbee2mqtt
#   ./logs.sh kiosk

if [[ "$1" == "kiosk" ]]; then
    sudo journalctl -u kiosk.service -f
elif [[ -n "$1" ]]; then
    sudo docker logs -f "$1"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    COMPOSE_FILE="$(dirname "$SCRIPT_DIR")/config/docker-compose.yml"
    sudo docker compose -f "$COMPOSE_FILE" logs -f
fi
