#!/bin/bash
set -euo pipefail

#===============================================================================
# Homelab Kiosk Setup — Home Assistant, Zigbee2MQTT, MQTT, X11 Kiosk
# Usage: sudo ./install.sh [options]
#
# Options:
#   --url <url>         Kiosk URL (default: http://localhost:8123)
#   --zigbee <device>   Zigbee adapter path (default: /dev/ttyUSB0)
#   --skip-kiosk        Skip kiosk/display setup
#   --skip-docker       Skip Docker installation
#   --skip-zigbee       Skip Zigbee2MQTT setup
#   --start             Start services after install
#   --help              Show this help
#===============================================================================

# Source library files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/containers.sh"
source "$SCRIPT_DIR/lib/services.sh"
source "$SCRIPT_DIR/lib/kiosk.sh"

# Defaults
KIOSK_URL="http://localhost:8123"
KIOSK_USER="kiosk"
ZIGBEE_DEVICE="/dev/ttyUSB0"
INSTALL_KIOSK=true
INSTALL_DOCKER=true
INSTALL_ZIGBEE=true
START_SERVICES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)         KIOSK_URL="$2"; shift 2 ;;
        --zigbee)      ZIGBEE_DEVICE="$2"; shift 2 ;;
        --skip-kiosk)  INSTALL_KIOSK=false; shift ;;
        --skip-docker) INSTALL_DOCKER=false; shift ;;
        --skip-zigbee) INSTALL_ZIGBEE=false; shift ;;
        --start)       START_SERVICES=true; shift ;;
        --help)
            echo "Usage: sudo ./install.sh [options]"
            echo "  --url <url>         Kiosk URL (default: http://localhost:8123)"
            echo "  --zigbee <device>   Zigbee adapter path (default: /dev/ttyUSB0)"
            echo "  --skip-kiosk        Skip kiosk/display setup"
            echo "  --skip-docker       Skip Docker installation"
            echo "  --skip-zigbee       Skip Zigbee2MQTT setup"
            echo "  --start             Start services after install"
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

# Detect architecture
ARCH=$(dpkg --print-architecture)
log_info "Architecture: $ARCH"

#===============================================================================
# Main
#===============================================================================
main() {
    log_info "=== Homelab Kiosk Setup ==="
    log_info "Kiosk URL: $KIOSK_URL"
    log_info "Zigbee device: $ZIGBEE_DEVICE"
    echo

    if [[ ! -e "$ZIGBEE_DEVICE" ]]; then
        log_warn "Zigbee device $ZIGBEE_DEVICE not found - you may need to adjust --zigbee"
    fi

    if $INSTALL_DOCKER; then
        install_docker
        setup_containers
        setup_compose_service
        setup_watchdog
        setup_config_backup
    fi

    if $INSTALL_KIOSK; then
        setup_kiosk
        setup_screen_control
    fi

    echo
    log_info "=== Setup Complete ==="
    echo
    echo "Commands:"
    echo "  systemctl start homelab      # Start containers"
    echo "  systemctl start kiosk        # Start kiosk display"
    echo "  docker compose -f $COMPOSE_FILE logs -f"
    echo "  screen-control on|off        # Control display"
    echo
    echo "Web interfaces (after start):"
    echo "  Home Assistant:  http://localhost:8123"
    echo "  Zigbee2MQTT:     http://localhost:8080"
    echo
    echo "Config locations:"
    echo "  Home Assistant:  $DATA_DIR/homeassistant/"
    echo "  Zigbee2MQTT:     $DATA_DIR/zigbee2mqtt/"
    echo "  Docker Compose:  $COMPOSE_FILE"
    echo

    local do_start=$START_SERVICES
    if ! $do_start && [[ -t 0 ]]; then
        read -p "Start services now? [y/N] " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] && do_start=true
    fi

    if $do_start; then
        systemctl start homelab
        log_info "Containers starting... (may take a few minutes for first pull)"

        if $INSTALL_KIOSK; then
            log_info "Waiting 30s for Home Assistant before starting kiosk..."
            sleep 30
            systemctl start kiosk
        fi
    fi
}

main "$@"
