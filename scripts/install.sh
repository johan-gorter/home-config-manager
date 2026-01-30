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

# Defaults
KIOSK_URL="http://localhost:8123"
KIOSK_USER="kiosk"
ZIGBEE_DEVICE="/dev/ttyUSB0"
INSTALL_KIOSK=true
INSTALL_DOCKER=true
INSTALL_ZIGBEE=true
START_SERVICES=false
DATA_DIR="/opt/homelab"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)        KIOSK_URL="$2"; shift 2 ;;
        --zigbee)     ZIGBEE_DEVICE="$2"; shift 2 ;;
        --skip-kiosk) INSTALL_KIOSK=false; shift ;;
        --skip-docker) INSTALL_DOCKER=false; shift ;;
        --skip-zigbee) INSTALL_ZIGBEE=false; shift ;;
        --start)      START_SERVICES=true; shift ;;
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
# Docker Installation
#===============================================================================
install_docker() {
    if command -v docker &>/dev/null; then
        log_info "Docker already installed: $(docker --version)"
        return 0
    fi

    log_info "Installing Docker..."
    
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log_info "Docker installed successfully"
}

#===============================================================================
# Home Assistant & Zigbee2MQTT Setup
#===============================================================================
setup_containers() {
    log_info "Setting up container directories..."

    mkdir -p "$DATA_DIR"/{homeassistant,mosquitto/{config,data,log}}
    if $INSTALL_ZIGBEE; then
        mkdir -p "$DATA_DIR/zigbee2mqtt"
    fi

    # Mosquitto config
    cat > "$DATA_DIR/mosquitto/config/mosquitto.conf" << 'EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF

    # Zigbee2MQTT config
    if $INSTALL_ZIGBEE; then
        cat > "$DATA_DIR/zigbee2mqtt/configuration.yaml" << EOF
homeassistant: true
permit_join: false
frontend:
  port: 8080
mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://mosquitto:1883
serial:
  port: $ZIGBEE_DEVICE
  adapter: zstack
advanced:
  log_level: info
  network_key: GENERATE
EOF
    fi

    # Docker Compose
    cat > "$DATA_DIR/docker-compose.yml" << EOF
services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    restart: unless-stopped
    privileged: true
    network_mode: host
    volumes:
      - $DATA_DIR/homeassistant:/config
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      - mosquitto

  mosquitto:
    container_name: mosquitto
    image: eclipse-mosquitto:2
    restart: unless-stopped
    ports:
      - "1883:1883"
    volumes:
      - $DATA_DIR/mosquitto/config:/mosquitto/config
      - $DATA_DIR/mosquitto/data:/mosquitto/data
      - $DATA_DIR/mosquitto/log:/mosquitto/log
EOF

    if $INSTALL_ZIGBEE; then
        cat >> "$DATA_DIR/docker-compose.yml" << EOF

  zigbee2mqtt:
    container_name: zigbee2mqtt
    image: koenkk/zigbee2mqtt
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - $DATA_DIR/zigbee2mqtt:/app/data
      - /run/udev:/run/udev:ro
    devices:
      - $ZIGBEE_DEVICE:/dev/ttyUSB0
    depends_on:
      - mosquitto
    environment:
      - TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
EOF
    fi

    # Set permissions
    chown -R root:root "$DATA_DIR"
    chmod -R 755 "$DATA_DIR"

    log_info "Container configs created at $DATA_DIR"
}

#===============================================================================
# Systemd service for Docker Compose
#===============================================================================
setup_compose_service() {
    cat > /etc/systemd/system/homelab.service << EOF
[Unit]
Description=Homelab Docker Compose Stack
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DATA_DIR
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --remove-orphans
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable homelab.service
    log_info "Homelab service enabled"
}

#===============================================================================
# Kiosk Setup
#===============================================================================
setup_kiosk() {
    log_info "Installing kiosk packages..."
    
    apt-get update
    # Add Mozilla PPA for non-snap Firefox ESR
    if ! apt-cache policy firefox-esr 2>/dev/null | grep -q mozillateam; then
        add-apt-repository -y ppa:mozillateam/ppa
        apt-get update
    fi

    apt-get install -y --no-install-recommends \
        xorg \
        xserver-xorg-video-intel \
        xserver-xorg-input-libinput \
        openbox \
        firefox-esr \
        fonts-liberation \
        unclutter \
        avahi-daemon

    # Create kiosk user
    if ! id "$KIOSK_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$KIOSK_USER"
        log_info "Created user: $KIOSK_USER"
    fi

    KIOSK_HOME="/home/$KIOSK_USER"
    mkdir -p "$KIOSK_HOME/.config/openbox"

    # Openbox autostart
    cat > "$KIOSK_HOME/.config/openbox/autostart" << EOF
# Disable screen blanking
xset s off
xset s noblank
xset -dpms

# Hide cursor after 1 second
unclutter -idle 1 &

# Wait for Home Assistant to be ready
echo "Waiting for Home Assistant..."
while ! curl -s -o /dev/null -w "%{http_code}" "$KIOSK_URL" | grep -q "200\|401"; do
    sleep 5
done
echo "Home Assistant ready"

# Start Firefox in kiosk mode
exec firefox-esr --kiosk "$KIOSK_URL"
EOF

    # .xinitrc
    cat > "$KIOSK_HOME/.xinitrc" << 'EOF'
exec openbox-session
EOF

    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME"

    # Kiosk user needs tty/video/render access for X11
    usermod -aG tty,video,render,input "$KIOSK_USER"

    # Allow non-root users to start X
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/Xwrapper.config << 'XWEOF'
allowed_users=anybody
needs_root_rights=yes
XWEOF

    # Auto-detect GPU and create Xorg config
    if ls /dev/dri/card* &>/dev/null; then
        DRI_CARD=$(ls /dev/dri/card* | head -1)
        log_info "Detected GPU: $DRI_CARD"
        cat > /etc/X11/xorg.conf.d/10-kiosk.conf << XORGEOF
Section "Device"
    Identifier "Graphics"
    Driver     "modesetting"
    Option     "kmsdev" "$DRI_CARD"
EndSection
XORGEOF
    fi

    # Kiosk systemd service
    cat > /etc/systemd/system/kiosk.service << EOF
[Unit]
Description=Kiosk Mode
After=homelab.service network-online.target
Wants=network-online.target homelab.service

[Service]
User=$KIOSK_USER
WorkingDirectory=$KIOSK_HOME
ExecStart=/usr/bin/startx -- vt7
Restart=on-failure
RestartSec=10
TTYPath=/dev/tty7
StandardInput=tty
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

    systemctl daemon-reload
    systemctl enable kiosk.service
    log_info "Kiosk service enabled"
}

#===============================================================================
# Screen control helper script
#===============================================================================
setup_screen_control() {
    cat > /usr/local/bin/screen-control << 'EOF'
#!/bin/bash
case "$1" in
    on)  DISPLAY=:0 xset dpms force on  ;;
    off) DISPLAY=:0 xset dpms force off ;;
    *)   echo "Usage: screen-control {on|off}" ;;
esac
EOF
    chmod +x /usr/local/bin/screen-control
    log_info "Screen control script installed: screen-control {on|off}"
}

#===============================================================================
# Watchdog for container health
#===============================================================================
setup_watchdog() {
    cat > /usr/local/bin/homelab-watchdog << 'EOF'
#!/bin/bash
# Restart unhealthy containers
cd /opt/homelab
for container in $(docker compose ps --services 2>/dev/null); do
    if ! docker ps --filter "name=$container" --filter "status=running" -q | grep -q .; then
        logger -t homelab-watchdog "Container $container not running, restarting..."
        docker compose up -d "$container"
    fi
done
EOF
    chmod +x /usr/local/bin/homelab-watchdog

    # Cron job every 5 minutes
    echo "*/5 * * * * root /usr/local/bin/homelab-watchdog" > /etc/cron.d/homelab-watchdog
    log_info "Watchdog cron installed"
}

#===============================================================================
# Main
#===============================================================================
main() {
    log_info "=== Homelab Kiosk Setup ==="
    log_info "Kiosk URL: $KIOSK_URL"
    log_info "Zigbee device: $ZIGBEE_DEVICE"
    echo

    # Check zigbee device
    if [[ ! -e "$ZIGBEE_DEVICE" ]]; then
        log_warn "Zigbee device $ZIGBEE_DEVICE not found - you may need to adjust --zigbee"
    fi

    if $INSTALL_DOCKER; then
        install_docker
        setup_containers
        setup_compose_service
        setup_watchdog
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
    echo "  docker compose -f $DATA_DIR/docker-compose.yml logs -f"
    echo "  screen-control on|off        # Control display"
    echo
    echo "Web interfaces (after start):"
    echo "  Home Assistant:  http://localhost:8123"
    echo "  Zigbee2MQTT:     http://localhost:8080"
    echo
    echo "Config locations:"
    echo "  Home Assistant:  $DATA_DIR/homeassistant/"
    echo "  Zigbee2MQTT:     $DATA_DIR/zigbee2mqtt/"
    echo "  Docker Compose:  $DATA_DIR/docker-compose.yml"
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