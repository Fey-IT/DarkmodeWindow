#!/bin/zsh
# Builds DarkmodeWindow.app and installs it to ~/Applications.
# Build products stay outside iCloud Drive.
set -euo pipefail

ROOT="${0:A:h:h}"
SCRATCH="$HOME/Library/Caches/DarkmodeWindow-build"
APP="$HOME/Applications/DarkmodeWindow.app"
SIGN_ID="${SIGN_ID:--}"   # "-" = ad-hoc; set SIGN_ID to a local certificate name for stable permissions

swift build -c release --package-path "$ROOT" --scratch-path "$SCRATCH"
BIN="$(swift build -c release --package-path "$ROOT" --scratch-path "$SCRATCH" --show-bin-path)/DarkmodeWindow"

pkill -x DarkmodeWindow 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DarkmodeWindow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_ID" --identifier de.fey-it.DarkmodeWindow "$APP"

echo "Installed: $APP"
