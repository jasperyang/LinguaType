#!/bin/bash
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
PKG="$BASE/dist/LinguaType-0.1.0-local.pkg"
[[ -f "$PKG" ]] || { echo "Missing $PKG; run build-linguatype.sh first." >&2; exit 1; }
echo "This is a locally built, unsigned package. macOS administrator approval is required."
sudo /usr/sbin/installer -pkg "$PKG" -target /
echo "Installed. Log out/in once, then add LinguaType under System Settings > Keyboard > Text Input if needed."
