[Unit]
Description=Kiosk Mode
After=homelab.service network-online.target
Wants=network-online.target homelab.service

[Service]
User={{KIOSK_USER}}
WorkingDirectory={{KIOSK_HOME}}
ExecStart=/usr/bin/startx -- vt7
Restart=on-failure
RestartSec=10
TTYPath=/dev/tty7
StandardInput=tty
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
