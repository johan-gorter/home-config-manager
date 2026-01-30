#!/bin/bash
# Kiosk and screen control setup

setup_kiosk() {
    log_info "Installing kiosk packages..."

    apt-get update
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
    render_template "$TEMPLATES_DIR/openbox-autostart.tpl" \
        "$KIOSK_HOME/.config/openbox/autostart" \
        "KIOSK_URL=$KIOSK_URL"

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
        local dri_card
        dri_card=$(ls /dev/dri/card* | head -1)
        log_info "Detected GPU: $dri_card"
        cat > /etc/X11/xorg.conf.d/10-kiosk.conf << XORGEOF
Section "Device"
    Identifier "Graphics"
    Driver     "modesetting"
    Option     "kmsdev" "$dri_card"
EndSection
XORGEOF
    fi

    # Kiosk systemd service
    render_template "$TEMPLATES_DIR/kiosk.service.tpl" \
        /etc/systemd/system/kiosk.service \
        "KIOSK_USER=$KIOSK_USER" \
        "KIOSK_HOME=$KIOSK_HOME"

    systemctl daemon-reload
    systemctl enable kiosk.service
    log_info "Kiosk service enabled"
}

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
