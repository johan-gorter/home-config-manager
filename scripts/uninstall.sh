#!/bin/bash
set -euo pipefail

#===============================================================================
# Homelab Kiosk Uninstall Script
# Usage: sudo ./uninstall.sh [options]
#
# Options:
#   --remove-docker     Also remove Docker and its apt repository
#   --remove-packages   Also remove kiosk-related apt packages
#   --remove-user       Also delete the kiosk user account
#   --yes               Skip confirmation prompts
#   --help              Show this help
#===============================================================================

REMOVE_DOCKER=false
REMOVE_PACKAGES=false
REMOVE_USER=false
SKIP_CONFIRM=false
KIOSK_USER="kiosk"
DATA_DIR="/opt/homelab"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

confirm() {
    if $SKIP_CONFIRM; then return 0; fi
    if [[ ! -t 0 ]]; then return 1; fi
    read -p "$1 [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remove-docker)   REMOVE_DOCKER=true; shift ;;
        --remove-packages) REMOVE_PACKAGES=true; shift ;;
        --remove-user)     REMOVE_USER=true; shift ;;
        --yes)             SKIP_CONFIRM=true; shift ;;
        --help)
            echo "Usage: sudo ./uninstall.sh [options]"
            echo "  --remove-docker     Also remove Docker and its apt repository"
            echo "  --remove-packages   Also remove kiosk-related apt packages"
            echo "  --remove-user       Also delete the kiosk user account"
            echo "  --yes               Skip confirmation prompts"
            echo "  --help              Show this help"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

log_info "=== Homelab Kiosk Uninstall ==="
echo

#===============================================================================
# Stop and disable services
#===============================================================================
for svc in kiosk homelab; do
    if systemctl is-active --quiet "$svc.service" 2>/dev/null; then
        log_info "Stopping $svc.service..."
        systemctl stop "$svc.service"
    fi
    if systemctl is-enabled --quiet "$svc.service" 2>/dev/null; then
        log_info "Disabling $svc.service..."
        systemctl disable "$svc.service"
    fi
done

#===============================================================================
# Stop and remove Docker containers and network
#===============================================================================
if command -v docker &>/dev/null; then
    for container in homeassistant mosquitto zigbee2mqtt; do
        if docker ps -a --filter "name=^${container}$" -q | grep -q .; then
            log_info "Removing container: $container"
            docker rm -f "$container" 2>/dev/null || true
        fi
    done

    if docker network ls --filter "name=homelab_default" -q | grep -q .; then
        log_info "Removing network: homelab_default"
        docker network rm homelab_default 2>/dev/null || true
    fi
fi

#===============================================================================
# Remove systemd unit files
#===============================================================================
for unit in /etc/systemd/system/homelab.service /etc/systemd/system/kiosk.service; do
    if [[ -f "$unit" ]]; then
        log_info "Removing $unit"
        rm -f "$unit"
    fi
done
systemctl daemon-reload

#===============================================================================
# Remove watchdog
#===============================================================================
for f in /etc/cron.d/homelab-watchdog /usr/local/bin/homelab-watchdog; do
    if [[ -f "$f" ]]; then
        log_info "Removing $f"
        rm -f "$f"
    fi
done

#===============================================================================
# Remove screen-control script
#===============================================================================
if [[ -f /usr/local/bin/screen-control ]]; then
    log_info "Removing /usr/local/bin/screen-control"
    rm -f /usr/local/bin/screen-control
fi

#===============================================================================
# Remove kiosk user config
#===============================================================================
KIOSK_HOME="/home/$KIOSK_USER"
if [[ -d "$KIOSK_HOME/.config/openbox" ]]; then
    log_info "Removing kiosk openbox config"
    rm -rf "$KIOSK_HOME/.config/openbox"
fi
if [[ -f "$KIOSK_HOME/.xinitrc" ]]; then
    log_info "Removing kiosk .xinitrc"
    rm -f "$KIOSK_HOME/.xinitrc"
fi
if [[ -f /etc/X11/xorg.conf.d/10-kiosk.conf ]]; then
    log_info "Removing /etc/X11/xorg.conf.d/10-kiosk.conf"
    rm -f /etc/X11/xorg.conf.d/10-kiosk.conf
fi

if $REMOVE_USER && id "$KIOSK_USER" &>/dev/null; then
    log_info "Removing user: $KIOSK_USER"
    userdel -r "$KIOSK_USER" 2>/dev/null || userdel "$KIOSK_USER"
fi

#===============================================================================
# Remove data directory
#===============================================================================
if [[ -d "$DATA_DIR" ]]; then
    if confirm "Remove $DATA_DIR? This contains Home Assistant and Zigbee2MQTT data."; then
        log_info "Removing $DATA_DIR"
        rm -rf "$DATA_DIR"
    else
        log_warn "Kept $DATA_DIR"
    fi
fi

#===============================================================================
# Optional: remove Docker
#===============================================================================
if $REMOVE_DOCKER; then
    log_info "Removing Docker..."
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.gpg
    apt-get autoremove -y
fi

#===============================================================================
# Optional: remove kiosk packages
#===============================================================================
if $REMOVE_PACKAGES; then
    log_info "Removing kiosk packages..."
    apt-get purge -y xorg xserver-xorg-video-intel xserver-xorg-input-libinput openbox firefox-esr fonts-liberation unclutter avahi-daemon 2>/dev/null || true
    apt-get autoremove -y
fi

echo
log_info "=== Uninstall Complete ==="
