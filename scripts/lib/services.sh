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
    local backup_script="$REPO_DIR/scripts/config-backup.sh"

    render_template "$TEMPLATES_DIR/homelab-config-backup.tpl" \
        "$backup_script" \
        "DATA_DIR=$DATA_DIR"
    chmod +x "$backup_script"

    echo "0 3 * * * root $backup_script" > /etc/cron.d/homelab-config-backup
    log_info "Config backup cron installed (runs nightly at 3 AM)"
}
