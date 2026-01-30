#!/bin/bash
sudo systemctl start homelab
echo "Homelab containers starting..."
sleep 5
sudo docker compose -f /home/jgo/workspace/config/docker-compose.yml ps
