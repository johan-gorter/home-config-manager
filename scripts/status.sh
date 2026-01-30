#!/bin/bash
echo "=== Services ==="
printf "  homelab: "; systemctl is-active homelab.service 2>/dev/null || echo "inactive"
printf "  kiosk:   "; systemctl is-active kiosk.service 2>/dev/null || echo "inactive"
echo
echo "=== Containers ==="
sudo docker compose -f /home/jgo/workspace/config/docker-compose.yml ps
