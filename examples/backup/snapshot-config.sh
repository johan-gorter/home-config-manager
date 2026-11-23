#!/bin/sh
# Place in tools/ of your private house repo.
# Copies the hand-editable config from /srv/homeassistant into config/ of this
# repo. Secrets are left out or redacted; .storage/, databases, logs and
# secrets.yaml never come along. Review `git diff` before committing.
set -eu
SRC=/srv/homeassistant
DST="$(cd "$(dirname "$0")/.." && pwd)/config"
mkdir -p "$DST/homeassistant" "$DST/zigbee2mqtt" "$DST/mosquitto"
sudo cat "$SRC/docker-compose.yml" > "$DST/docker-compose.yml"
for f in configuration.yaml automations.yaml scripts.yaml scenes.yaml; do
    sudo cat "$SRC/homeassistant/$f" > "$DST/homeassistant/$f"
done
sudo cat "$SRC/zigbee2mqtt/configuration.yaml" \
    | sed -E 's/^( *(auth_token|network_key|password|pan_id_secret): *).*/\1<redacted>/' \
    > "$DST/zigbee2mqtt/configuration.yaml"
sudo cat "$SRC/mosquitto/config/mosquitto.conf" > "$DST/mosquitto/mosquitto.conf"
echo "Snapshot written to $DST"
