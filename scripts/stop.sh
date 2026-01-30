#!/bin/bash
sudo systemctl stop kiosk 2>/dev/null
sudo systemctl stop homelab
echo "All services stopped."
