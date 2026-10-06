#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="${1:-Client}"

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building $SCHEME"
xcodebuild \
  -project Rater.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -skipMacroValidation \
  -derivedDataPath build \
  build | tail -20

if [ "$SCHEME" != "Client" ]; then
  exit 0
fi

APP="build/Build/Products/Debug/Rater.app"
echo "==> Launching $APP"
pkill -f "Rater.app/Contents/MacOS/Rater" 2>/dev/null || true
open "$APP"
