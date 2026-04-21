#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build"
APP_NAME="NaverCalDAVViewer"

mkdir -p "$OUT_DIR"

swiftc \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  "$ROOT_DIR"/Sources/NaverCalDAVViewer/*.swift \
  -o "$OUT_DIR/$APP_NAME"

echo "Built: $OUT_DIR/$APP_NAME"
