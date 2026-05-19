#!/bin/bash
# Build ClaudeWidget Release and pack it into a drag-to-Applications DMG.
# Output: build/ClaudeWidget.dmg
set -euo pipefail

# Always run from the project root
cd "$(dirname "$0")/.."

VERSION="$(awk -F'"' '/CFBundleShortVersionString:/ {print $2; exit}' project.yml)"
: "${VERSION:=0.1.0}"
APP_NAME="ClaudeWidget"
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="build/${DMG_NAME}.dmg"

echo "▶  Generating Xcode project…"
xcodegen >/dev/null

echo "▶  Building Release…"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath build/ \
    build \
    >/tmp/xcodebuild.log 2>&1 || { tail -40 /tmp/xcodebuild.log; exit 1; }

APP_PATH="build/Build/Products/Release/${APP_NAME}.app"
[[ -d "$APP_PATH" ]] || { echo "✗  Build did not produce ${APP_PATH}"; exit 1; }

echo "▶  Re-signing with stable identifier…"
codesign --force --sign - \
    --identifier "com.tobyhinshaw.claudewidget" \
    --options runtime \
    --entitlements ClaudeWidget.entitlements \
    --deep "$APP_PATH" 2>&1 | grep -v "replacing existing signature" || true

echo "▶  Staging DMG contents…"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▶  Creating ${DMG_PATH}…"
rm -f "$DMG_PATH"
mkdir -p build
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG_PATH" \
    >/dev/null

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
echo "✓  ${DMG_PATH}  (${SIZE})"
echo
echo "Install:  open ${DMG_PATH}  →  drag ClaudeWidget to Applications"
