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
  install.sh      # Full homelab + kiosk provisioning
  uninstall.sh    # Reverses install.sh (with confirmation prompts)
  start.sh        # Start homelab containers
  stop.sh         # Stop kiosk + containers
  status.sh       # Show service and container status
  logs.sh         # View logs (all, per-container, or kiosk)
```

## Scripts

### install.sh

```bash
sudo ./scripts/install.sh [options]
```

Options: `--url <url>`, `--zigbee <device>`, `--skip-kiosk`, `--skip-docker`, `--skip-zigbee`, `--start`, `--help`

Defaults: URL `http://localhost:8123`, Zigbee device `/dev/ttyUSB0`.

Functions executed by `main()`:
1. **install_docker()** — Docker + Compose installation
2. **setup_containers()** — Creates `config/`, generates configs and `docker-compose.yml`
3. **setup_compose_service()** — Registers `homelab.service` systemd unit
4. **setup_kiosk()** — X.org/Openbox/Firefox ESR kiosk, `kiosk` user, `kiosk.service`
5. **setup_screen_control()** — `/usr/local/bin/screen-control` utility
6. **setup_watchdog()** — Cron job restarting unhealthy containers every 5 min

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
