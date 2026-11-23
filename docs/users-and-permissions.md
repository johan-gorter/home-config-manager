# Users and permissions

| User | Purpose |
|---|---|
| `<admin>` | Your own account. Administration, sudo. Member of group `homeassistant` |
| `homeassistant` (system user, `nologin`) | Owns the service data |
| `kiosk` (only with a kiosk) | Logged in automatically; runs only the dashboard. Password locked |

## The data directory

```bash
sudo groupadd --system homeassistant
sudo useradd --system --gid homeassistant --no-create-home --shell /usr/sbin/nologin homeassistant
sudo usermod -aG homeassistant <admin>          # log out and back in afterwards

sudo mkdir -p /srv/homeassistant
sudo chown -R root:homeassistant /srv/homeassistant
sudo chmod 750 /srv/homeassistant
sudo find /srv/homeassistant -type d -exec chmod g+s {} +             # setgid on every directory
sudo setfacl -R -m g:homeassistant:rwX /srv/homeassistant              # current files
sudo setfacl -R -d -m g:homeassistant:rwX /srv/homeassistant           # default ACL for new files
```

**Why setgid plus a default ACL.** The containers run as root and create files as
root. Without these two, within a week you cannot edit files HA created without
sudo. Setgid makes new files belong to group `homeassistant`; the default ACL
makes them group-writable. Together they let the admin edit YAML without sudo.

Containers that drop to their own user need an extra ACL for that uid on their
directories. Mosquitto runs as uid 1883, InfluxDB and the Matter server as uid
1000:

```bash
sudo setfacl -R -m u:1883:rwX -m d:u:1883:rwX /srv/homeassistant/mosquitto/data
```

**Never `chmod -R 755`.** `.storage/core.config_entries` and `secrets.yaml` hold
every integration's credentials in plain text and must not be readable by
`kiosk` or other users.

## What is and is not a security boundary

- **`homeassistant` is not a security boundary.** Docker runs as root and starts
  the containers as root; HA effectively has more power than your admin account.
  That is accepted: HA is trusted software. The user exists for file ownership;
  the group does the actual work.
- **Membership of the `docker` group equals root.** Keep it empty, or at least
  keep `kiosk` out of it.
- **`kiosk` is the one real boundary**: anyone standing at the screen is using
  that account. Keep it out of every group it does not strictly need — in
  particular not `input` (read access to every keyboard: effectively a
  keylogger) and not `video`/`render` (logind grants device access per seat).
  See [kiosk.md](kiosk.md).
- **Physical access is out of scope** for a home server: whoever has the laptop
  in hand is root. No disk encryption or BIOS password, so the machine can boot
  unattended after a power cut. That is a deliberate trade-off.
