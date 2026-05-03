#!/usr/bin/env bash
# Dumpster iOS — one-shot terminal build + install + launch
# Usage:  ./run.sh           (uses default sim: iPhone 17 Pro)
#         ./run.sh "iPhone 16"   (any device name from `xcrun simctl list devices`)

set -e

DEVICE_NAME="${1:-iPhone 17 Pro}"
BUNDLE_ID="com.leescott.dumpster.ios"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="DumpsterIOS"

echo "→ Finding simulator: $DEVICE_NAME"
DEVICE_ID=$(xcrun simctl list devices available -j \
  | /usr/bin/python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for v in d.values() for x in v if x['name']=='$DEVICE_NAME'))")

if [ -z "$DEVICE_ID" ]; then
  echo "✗ Simulator '$DEVICE_NAME' not found. List with: xcrun simctl list devices"
  exit 1
fi
echo "  $DEVICE_ID"

echo "→ Booting simulator (if needed)…"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator

echo "→ Building…"
cd "$PROJECT_DIR"
xcodebuild \
  -project DumpsterIOS.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "id=$DEVICE_ID" \
  -quiet \
  build

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/DumpsterIOS-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "DumpsterIOS.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
  echo "✗ Could not locate built .app"
  exit 1
fi
echo "  $APP_PATH"

echo "→ Installing…"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

echo "→ Launching…"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

echo "✓ Done."
