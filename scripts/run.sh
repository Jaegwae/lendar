#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/build.sh"
"$ROOT_DIR/build/NaverCalDAVViewer" >/tmp/naver-caldav-viewer.log 2>&1 &
APP_PID=$!
disown "$APP_PID" 2>/dev/null || true
echo "Launched NaverCalDAVViewer (pid=$APP_PID)"
