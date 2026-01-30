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
    sudo docker compose -f /opt/homelab/docker-compose.yml logs -f
fi
