#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="MyInvest"
APP_DISPLAY_NAME="Vestor"
BUNDLE_ID="com.vestor.desktop"
MIN_SYSTEM_VERSION="14.0"
UPDATE_FEED_URL="https://ganbarovemin.github.io/Vestor/appcast.xml"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${VESTOR_RUN_DIR:-${TMPDIR:-/tmp}/vestor-debug-${UID:-local}}"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
LEGACY_APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VERSION_JSON="$ROOT_DIR/release/version.json"
PUBLIC_KEY_FILE="$ROOT_DIR/release/sparkle-public-ed-key.txt"

cd "$ROOT_DIR"

pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$VERSION_JSON")"
BUILD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$VERSION_JSON")"
PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
if [[ -z "$PUBLIC_ED_KEY" && -f "$PUBLIC_KEY_FILE" ]]; then
  PUBLIC_ED_KEY="$(tr -d '\n' < "$PUBLIC_KEY_FILE")"
fi
if [[ -z "$PUBLIC_ED_KEY" ]]; then
  PUBLIC_ED_KEY="UNCONFIGURED-SPARKLE-PUBLIC-KEY"
fi

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
if [[ "$LEGACY_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
  rm -rf "$LEGACY_APP_BUNDLE"
fi
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
ditto --noextattr --noqtn "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
ditto --noextattr --noqtn "$ROOT_DIR/Resources/Brand/VestorLogo.png" "$APP_RESOURCES/VestorLogo.png"

SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -path '*Sparkle.framework' -type d | grep -E 'macos|Sparkle.framework$' | head -n 1 || true)"
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
  ditto --norsrc --noextattr --noqtn "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
  if ! otool -l "$APP_BINARY" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  fi
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUEnableInstallerLauncherService</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$UPDATE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null

if command -v codesign >/dev/null; then
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
  xattr -crs "$APP_BUNDLE" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$PRODUCT_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
