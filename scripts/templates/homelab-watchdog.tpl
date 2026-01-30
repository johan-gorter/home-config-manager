#!/bin/bash
# Restart unhealthy containers
cd {{DATA_DIR}}
for container in $(docker compose ps --services 2>/dev/null); do
    if ! docker ps --filter "name=$container" --filter "status=running" -q | grep -q .; then
        logger -t homelab-watchdog "Container $container not running, restarting..."
        docker compose up -d "$container"
    fi
done
