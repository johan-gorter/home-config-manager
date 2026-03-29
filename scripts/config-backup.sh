#!/bin/bash
set -euo pipefail

DATA_DIR="/home/jgo/workspace/config"

if [ "$(id -u)" -eq 0 ]; then
    OWNER=$(stat -c '%U:%G' "$DATA_DIR")
    chown -R "$OWNER" "$DATA_DIR"
    RUN="sudo -u ${OWNER%%:*}"
else
    RUN=""
fi

cd "$DATA_DIR"
$RUN git add -A
$RUN git diff --cached --quiet || $RUN git commit -m "auto-backup $(date)"
$RUN git push 2>/dev/null || true
