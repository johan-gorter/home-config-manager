#!/bin/bash
# Container config generation

setup_containers() {
    log_info "Setting up container directories..."

    mkdir -p "$DATA_DIR"/{homeassistant,mosquitto/{config,data,log}}
    if $INSTALL_ZIGBEE; then
        mkdir -p "$DATA_DIR/zigbee2mqtt"
    fi

    local tz
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")

    # Mosquitto config (static, no substitution needed)
    cp "$TEMPLATES_DIR/mosquitto.conf" "$DATA_DIR/mosquitto/config/mosquitto.conf"

    # Zigbee2MQTT config
    if $INSTALL_ZIGBEE; then
        render_template "$TEMPLATES_DIR/zigbee2mqtt.yaml.tpl" \
            "$DATA_DIR/zigbee2mqtt/configuration.yaml" \
            "ZIGBEE_DEVICE=$ZIGBEE_DEVICE"
    fi

    # Docker Compose
    render_template "$TEMPLATES_DIR/docker-compose.yml.tpl" \
        "$COMPOSE_FILE" \
        "DATA_DIR=$DATA_DIR" \
        "ZIGBEE_DEVICE=$ZIGBEE_DEVICE" \
        "TZ=$tz"

    # Remove zigbee2mqtt block if skipped
    if ! $INSTALL_ZIGBEE; then
        sed -i '/^  # BEGIN zigbee2mqtt/,/^  # END zigbee2mqtt/d' "$COMPOSE_FILE"
    fi

    chown -R root:root "$DATA_DIR"
    chmod -R 755 "$DATA_DIR"

    log_info "Container configs created at $DATA_DIR"
}
