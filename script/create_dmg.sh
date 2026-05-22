#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Vestor"
VERSION_JSON="$ROOT_DIR/release/version.json"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$VERSION_JSON")"
DMG_DIR="$ROOT_DIR/dist/dmg"
STAGING_DIR="${TMPDIR:-/tmp}/vestor-dmg-staging-${UID:-local}"
DMG_PATH="$DMG_DIR/$APP_NAME-$VERSION.dmg"

cd "$ROOT_DIR"

APP_BUNDLE="$("$ROOT_DIR/script/build_release.sh")"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DMG_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
