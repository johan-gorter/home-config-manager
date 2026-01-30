# CLAUDE.md

Claude Code is managing and configuring this homelab server. The user has basic Linux knowledge — prefer clear explanations, avoid jargon, and run commands directly rather than asking the user to do so.

## Environment

- Passwordless sudo is configured — use `sudo` freely without `-S` or askpass
- OS: Ubuntu (amd64)
- Hostname: `silver` (reachable as `silver.local` via Avahi/mDNS)
- Zigbee adapter: CH340-based on `/dev/ttyUSB0` (adapter type: `zstack`)
- GPU: Intel GeminiLake UHD 605 (`/dev/dri/card1`)
- Display: eDP laptop panel on VT7, kiosk runs Firefox ESR

## Project Structure

```
scripts/
  install.sh          # Slim orchestrator — sources lib files, parses args, calls functions
  uninstall.sh        # Slim orchestrator — sources lib/common.sh, does removal
  lib/
    common.sh         # Shared: paths, colors, logging, render_template()
    docker.sh         # install_docker()
    containers.sh     # setup_containers() — renders templates into config/
    services.sh       # setup_compose_service(), setup_watchdog(), setup_config_backup()
    kiosk.sh          # setup_kiosk(), setup_screen_control()
  templates/
    docker-compose.yml.tpl
    mosquitto.conf
    zigbee2mqtt.yaml.tpl
    homelab.service.tpl
    kiosk.service.tpl
    openbox-autostart.tpl
    homelab-watchdog.tpl
    homelab-config-backup.tpl
  start.sh            # Sources common.sh for COMPOSE_FILE
  stop.sh             # Stop kiosk + containers
  status.sh           # Sources common.sh for COMPOSE_FILE
  logs.sh             # Sources common.sh for COMPOSE_FILE
```

## Scripts

### install.sh

```bash
sudo ./scripts/install.sh [options]
```

Options: `--url <url>`, `--zigbee <device>`, `--skip-kiosk`, `--skip-docker`, `--skip-zigbee`, `--start`, `--help`

Defaults: URL `http://localhost:8123`, Zigbee device `/dev/ttyUSB0`.

Functions executed by `main()`:
1. **install_docker()** — Docker + Compose installation (`lib/docker.sh`)
2. **setup_containers()** — Creates `config/`, renders templates into configs (`lib/containers.sh`)
3. **setup_compose_service()** — Registers `homelab.service` systemd unit (`lib/services.sh`)
4. **setup_watchdog()** — Cron job restarting unhealthy containers every 5 min (`lib/services.sh`)
5. **setup_config_backup()** — Nightly git-based config backup at 3 AM (`lib/services.sh`)
6. **setup_kiosk()** — X.org/Openbox/Firefox ESR kiosk, `kiosk` user, `kiosk.service` (`lib/kiosk.sh`)
7. **setup_screen_control()** — `/usr/local/bin/screen-control` utility (`lib/kiosk.sh`)

### uninstall.sh

```bash
sudo ./scripts/uninstall.sh [options]
```

Options: `--remove-docker`, `--remove-packages`, `--remove-user`, `--yes`, `--help`

Removes services, containers, configs, and data. Does not remove Docker or apt packages unless explicitly requested.

### Helper scripts

| Script | Usage |
|---|---|
| `./scripts/start.sh` | Start containers, show status |
| `./scripts/stop.sh` | Stop kiosk + containers |
| `./scripts/status.sh` | Show service and container status |
| `./scripts/logs.sh` | All container logs (live) |
| `./scripts/logs.sh homeassistant` | Single container logs |
| `./scripts/logs.sh kiosk` | Kiosk/X11 journal logs |

## Web UIs

- Home Assistant: `http://silver.local:8123`
- Zigbee2MQTT: `http://silver.local:8080`

## Key Design Decisions

- Multi-arch support via `dpkg --print-architecture`
- Kiosk uses Firefox ESR (non-snap) since Ubuntu's Chromium snap doesn't work in systemd services
- Kiosk runs on VT7 (`Ctrl+Alt+F7` to view, `Ctrl+Alt+F1` for terminal)
- Kiosk waits for Home Assistant HTTP endpoint before launching Firefox
- Zigbee2MQTT uses `adapter: zstack` and inherits system timezone
- Avahi broadcasts `silver.local` for network-wide access
- Scripts handle non-interactive execution (no TTY) gracefully
- Scripts use `set -euo pipefail` with color-coded logging
- Config files are generated from `scripts/templates/` via `render_template()` (`{{VAR}}` substitution)
- Nightly config backup via git commit+push in `config/` (cron at 3 AM)
