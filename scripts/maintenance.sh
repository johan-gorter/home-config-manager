#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log() { logger -t homelab-maintenance "$1"; log_info "$1"; }

log "Starting maintenance"

# OS updates
log "Updating OS packages"
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq

# Docker image updates (pull latest, restart if changed)
log "Pulling latest Docker images"
docker compose -f "$COMPOSE_FILE" pull --quiet
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# Claude Code update (runs as the repo owner, not root)
OWNER=$(stat -c '%U' "$REPO_DIR")
log "Updating Claude Code"
sudo -u "$OWNER" /home/"$OWNER"/.local/bin/claude update --yes 2>&1 || \
    log "Claude Code update skipped or already up to date"

log "Maintenance complete"
