#!/bin/bash
set -euo pipefail
cd {{DATA_DIR}}
git add -A
git diff --cached --quiet || git commit -m "auto-backup $(date)"
git push 2>/dev/null || true
