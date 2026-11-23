# Backup

Two separate things:

1. **restic** — encrypted, deduplicated, append-only backups of everything
   needed to rebuild the server, stored offsite.
2. **git** — a readable history of the hand-editable YAML, in the private house
   repo.

## What goes in

- The HA config directory **including `.storage/`**: integrations, devices,
  users and credentials live there. Without it a restore is not a restore.
- **`zigbee2mqtt/coordinator_backup.json`** — network key and device table. The
  single most valuable file: without it, a coordinator failure means re-pairing
  every device and redoing every bind. Plus `configuration.yaml` and
  `database.db` next to it.
- The Matter server's data (fabric keys) and Mosquitto's persistence.
- `docker-compose.yml` and the rest of `/srv/homeassistant`.
- `/etc` — systemd units, firewall, WireGuard, udev rules: cheap and saves an
  evening of reconstruction.
- **Long-term history (InfluxDB)** — the only truly irreplaceable data. Config
  can be recreated; two years of temperature history cannot.

## What stays out

- `home-assistant_v2.db` — short-term history for the UI. Hundreds of MB that
  change every second and deduplicate badly.
- Logs, `tts/`, `deps/`, `.cache/`.
- The live InfluxDB data directory — back up a dump instead (below).

## Design

- **restic** encrypts on the server. The password never leaves it (and your
  password manager). A compromised backup host yields only encrypted blobs.
- **Append-only** target: `rclone serve restic --append-only` (or `rest-server
  --append-only`) on a VPS, reachable only over the WireGuard tunnel from
  [remote-access.md](remote-access.md), with its own login. The server can add
  backups but never delete or overwrite them — so a compromised or broken server
  cannot destroy its own backups exactly when you need them.
  [`examples/backup/rclone-restic.service`](../examples/backup/rclone-restic.service).
- **Why not `rsync`/`scp`:** no encryption on a public machine, no
  deduplication (a full copy every night, or overwriting and no history), and a
  login that can write can also delete.
- **Name the repository after the role** (`ha`), not the machine. A future
  machine that takes over continues the same backup.
- **Consistent database dumps first.** Copying a running database can catch a
  half-written file, and you find out only when restoring. Dump InfluxDB with
  `influx backup` before restic runs. HA's `.storage`, Zigbee2MQTT and Matter
  write their files atomically, so those are safe to copy live.
- **systemd timer, not cron:** better logging, no overlapping runs, and
  `Persistent=true` catches up after downtime.
- **Pruning is manual.** Because the server is append-only, `restic forget
  --prune` is a deliberate job run on the backup host (say, yearly). Suggested
  retention: 7 daily, 4 weekly, 6 monthly, and monthly snapshots kept forever
  for the long-term data.
- **Store the restic password and repository ID in a password manager.**
  Encryption is the point — and also how people lose their backups.

Example: [`examples/backup/ha-backup`](../examples/backup/ha-backup) with its
[service](../examples/backup/ha-backup.service) and
[timer](../examples/backup/ha-backup.timer). Volume stays small: configuration
is a few hundred MB, InfluxDB adds roughly 1–2 GB a year after compression.

## Monitoring

A backup you are not sure runs is not a backup. The example script publishes a
retained MQTT message on success, which shows up in HA as a timestamp sensor
through MQTT discovery. An automation warns when it is **older than 48 hours** —
not 24: one missed night (VPS maintenance) should not alarm you, or you learn to
ignore the warning
([`examples/homeassistant/monitoring-automations.yaml`](../examples/homeassistant/monitoring-automations.yaml)).

## Restore test

Untested is invalid. After the first backup:

```bash
sudo bash -c 'set -a; . /root/.config/restic/ha.env; set +a; restic snapshots'
sudo bash -c 'set -a; . /root/.config/restic/ha.env; set +a; restic restore latest --target /tmp/restore-test'
```

Compare `coordinator_backup.json` with the original, and load the InfluxDB dump
into a throwaway container to count the points. Repeat now and then.

Also check that deleting is refused: `restic forget` from the server must fail
with 403.

## Git for the YAML

A private repo with only the hand-editable files — `configuration.yaml`,
`automations.yaml`, `scripts.yaml`, `scenes.yaml`, Zigbee2MQTT's
`configuration.yaml` with secrets redacted, `docker-compose.yml`. **Never**
`.storage/`, databases, `secrets.yaml` or `coordinator_backup.json`: those
contain tokens and keys and belong in the encrypted backup only.

[`examples/backup/snapshot-config.sh`](../examples/backup/snapshot-config.sh)
copies these into the house repo; run it after changing config through the UI or
API, read `git diff`, commit. The diff is a good review of what changed.

Do not turn `/srv/homeassistant` itself into a git repo that commits everything:
that pushes `.storage/` with plain-text tokens and a database of hundreds of MB.
