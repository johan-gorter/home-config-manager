#!/bin/bash
sudo systemctl start homelab
echo "Homelab containers starting..."
sleep 5
sudo docker compose -f /opt/homelab/docker-compose.yml ps
