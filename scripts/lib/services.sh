#!/bin/bash
# Systemd service, watchdog, and config backup setup

setup_compose_service() {
    render_template "$TEMPLATES_DIR/homelab.service.tpl" \
        /etc/systemd/system/homelab.service \
        "DATA_DIR=$DATA_DIR"

    systemctl daemon-reload
    systemctl enable homelab.service
    log_info "Homelab service enabled"
}

setup_watchdog() {
    render_template "$TEMPLATES_DIR/homelab-watchdog.tpl" \
        /usr/local/bin/homelab-watchdog \
        "DATA_DIR=$DATA_DIR"
    chmod +x /usr/local/bin/homelab-watchdog

    echo "*/5 * * * * root /usr/local/bin/homelab-watchdog" > /etc/cron.d/homelab-watchdog
    log_info "Watchdog cron installed"
}

setup_config_backup() {
    local backup_user
    backup_user=$(stat -c '%U' "$DATA_DIR")

    render_template "$TEMPLATES_DIR/homelab-config-backup.tpl" \
        /usr/local/bin/homelab-config-backup \
        "DATA_DIR=$DATA_DIR"
    chmod +x /usr/local/bin/homelab-config-backup

    echo "0 3 * * * $backup_user /usr/local/bin/homelab-config-backup" > /etc/cron.d/homelab-config-backup
    log_info "Config backup cron installed (runs nightly at 3 AM as $backup_user)"
}
