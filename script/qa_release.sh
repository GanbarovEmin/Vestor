#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 script/prepare_brand_assets.py
swift test
./script/build_and_run.sh --verify
APP_BUNDLE="$(./script/build_release.sh)"
DMG_PATH="$(./script/create_dmg.sh)"

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
test -x "$APP_BUNDLE/Contents/MacOS/MyInvest"
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -f "$APP_BUNDLE/Contents/Resources/VestorLogo.png"
test -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

sips -g pixelWidth -g pixelHeight Resources/Brand/VestorLogo.png | grep -q "pixelWidth"
sips -g pixelWidth -g pixelHeight Resources/Brand/vestor-app-icon-1024.png | grep -q "1024"
codesign --verify --deep --strict "$APP_BUNDLE"

MOUNT_DIR="$(mktemp -d)"
cleanup() {
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_DIR" >/dev/null
test -d "$MOUNT_DIR/Vestor.app"
test -L "$MOUNT_DIR/Applications"
shasum -a 256 -c "$DMG_PATH.sha256"

echo "QA release checks passed for $DMG_PATH"
