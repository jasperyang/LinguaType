#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$BASE/LinguaTypeCompanion"
BUILD_ROOT="$BASE/.build/companion"
APP="$BUILD_ROOT/LinguaTypeCompanion.app"
BIN="$APP/Contents/MacOS/LinguaTypeCompanion"
INSTALL_ROOT="$HOME/Applications"
INSTALLED_APP="$INSTALL_ROOT/LinguaTypeCompanion.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: LinguaType Companion must be built on macOS." >&2
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "ERROR: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

echo "==> Running Companion regression tests"
"$BASE/test-companion.sh"

echo "==> Building LinguaTypeCompanion.app"
/bin/rm -rf "$BUILD_ROOT"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/usr/bin/swiftc -O \
  -target "$ARCH-apple-macos15" \
  -framework Cocoa -framework Carbon -framework Foundation \
  -framework ApplicationServices -framework SwiftUI \
  -framework Translation -framework NaturalLanguage \
  "$SOURCE_ROOT"/Sources/*.swift \
  -o "$BIN"
/bin/cp "$SOURCE_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - \
  --entitlements "$SOURCE_ROOT/LinguaTypeCompanion.entitlements" \
  "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

echo "==> Installing to $INSTALLED_APP"
/bin/mkdir -p "$INSTALL_ROOT"
/usr/bin/pkill -x LinguaTypeCompanion 2>/dev/null || true
/bin/rm -rf "$INSTALLED_APP"
/bin/cp -R "$APP" "$INSTALLED_APP"
/usr/bin/xattr -cr "$INSTALLED_APP" 2>/dev/null || true

if [[ -f "$HOME/Library/LaunchAgents/io.linguatype.companion.plist" ]]; then
  /bin/launchctl kickstart -k "gui/$(id -u)/io.linguatype.companion" 2>/dev/null || true
else
  /usr/bin/open -g "$INSTALLED_APP"
fi

echo "==> Installed. Look for A·あ in the macOS menu bar."
echo "    First launch requires Accessibility permission in System Settings."
