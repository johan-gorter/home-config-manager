#!/bin/bash
# Shared variables, colors, logging, and utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$REPO_DIR/config"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# render_template TEMPLATE OUTPUT VAR=VALUE ...
render_template() {
    local template="$1" output="$2"; shift 2
    cp "$template" "$output"
    while [[ $# -gt 0 ]]; do
        sed -i "s|{{${1%%=*}}}|${1#*=}|g" "$output"
        shift
    done
}
