#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="GanbarovEmin/Vestor"
PAGES_BASE="https://ganbarovemin.github.io/Vestor"
VERSION_JSON="$ROOT_DIR/release/version.json"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$VERSION_JSON")"
BUILD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$VERSION_JSON")"
TAG="v$VERSION"
APPCAST="$ROOT_DIR/docs/appcast.xml"
RELEASE_NOTES="$ROOT_DIR/release/release-notes-$VERSION.md"
PUBLIC_KEY_FILE="$ROOT_DIR/release/sparkle-public-ed-key.txt"

cd "$ROOT_DIR"

if [[ ! -s "$PUBLIC_KEY_FILE" ]]; then
  echo "Missing $PUBLIC_KEY_FILE. Generate Sparkle keys first and store only the public key there." >&2
  exit 1
fi

DMG_PATH="$(./script/create_dmg.sh)"
SHA_PATH="$DMG_PATH.sha256"
DMG_NAME="$(basename "$DMG_PATH")"
DMG_URL="https://github.com/$REPO/releases/download/$TAG/$DMG_NAME"
DMG_SIZE="$(stat -f%z "$DMG_PATH")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"

SPARKLE_TOOLS_DIR="$(find "$ROOT_DIR/.build" -type f -name sign_update -perm -111 -print -quit | xargs dirname 2>/dev/null || true)"
ED_SIGNATURE=""
if [[ -n "$SPARKLE_TOOLS_DIR" && -x "$SPARKLE_TOOLS_DIR/sign_update" ]]; then
  SIGN_OUTPUT="$("$SPARKLE_TOOLS_DIR/sign_update" --account Vestor "$DMG_PATH")"
  ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)"
fi
if [[ -z "$ED_SIGNATURE" ]]; then
  echo "Could not generate Sparkle EdDSA signature for $DMG_PATH" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/docs"
cat >"$APPCAST" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Vestor Updates</title>
    <link>$PAGES_BASE/</link>
    <description>Vestor macOS app update feed.</description>
    <language>en</language>
    <item>
      <title>Vestor $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
$(sed 's/$/<br \/>/' "$RELEASE_NOTES")
      ]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="$DMG_URL"
                 sparkle:edSignature="$ED_SIGNATURE"
                 length="$DMG_SIZE"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

python3 - "$ROOT_DIR/docs/index.html" "$DMG_URL" "$VERSION" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
dmg_url = sys.argv[2]
version = sys.argv[3]
text = path.read_text()
text = text.replace("{{LATEST_DMG_URL}}", dmg_url)
text = text.replace("{{LATEST_VERSION}}", version)
path.write_text(text)
PY

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" "$DMG_PATH" "$SHA_PATH" \
    --repo "$REPO" \
    --title "Vestor $VERSION" \
    --notes-file "$RELEASE_NOTES" \
    --draft=false \
    --prerelease
else
  gh release upload "$TAG" "$DMG_PATH" "$SHA_PATH" --repo "$REPO" --clobber
fi

echo "$APPCAST"
