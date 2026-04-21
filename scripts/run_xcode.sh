#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/NaverCalendar.xcodeproj"
SCHEME="NaverCalendarViewer"
CONFIGURATION="Debug"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  build

APP_PATH="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk '
        /BUILT_PRODUCTS_DIR = / { build=$3 }
        /FULL_PRODUCT_NAME = / { product=$3 }
        END { if (build != "" && product != "") print build "/" product }
      '
)"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Failed to locate built app bundle"
  exit 1
fi

open "$APP_PATH"
echo "Opened $APP_PATH"
