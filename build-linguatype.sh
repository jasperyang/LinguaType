#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
PINNED_RIMES_COMMIT="eba5185a3ed637b6df9ca9149fbfc49740bd58b2"
WORK="$BASE/work/rimes"
DIST="$BASE/dist"
# librime runtime cache — pre-fetched so build_install.sh's fetch-rime.sh does
# not have to re-download the Squirrel.pkg + Octagram model from GitHub on every
# run. Values mirror the upstream-pinned release (signed by Developer ID
# 28HU5A7B46) and are verified again before the cache is handed off.
SQUIRREL_PKG_URL="https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg"
SQUIRREL_PKG_BYTES="25498033"
SQUIRREL_PKG_SHA256="614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287"
SQUIRREL_CACHE="$WORK/Vendor/.cache/Squirrel-1.1.2.pkg"
OCTAGRAM_MODEL="zh-hans-t-essay-bgw.gram"
OCTAGRAM_MODEL_URL="https://raw.githubusercontent.com/lotem/rime-octagram-data/f8ce3b534733e489a8470a7c2adf5a154e8ea069/${OCTAGRAM_MODEL}"
OCTAGRAM_MODEL_BYTES="40925228"
OCTAGRAM_MODEL_SHA256="d3cb2438c1fdcd6a855dd6ca8f5c1060a29273c6b64c2c2c69af67cd71b6aa7e"
OCTAGRAM_CACHE="$WORK/Vendor/.cache/$OCTAGRAM_MODEL"

echo "==> LinguaType 0.1 local builder"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: this builder must run on macOS 15+ (current: $(uname -s))." >&2
  exit 1
fi

MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$MAJOR" -lt 15 ]]; then
  echo "ERROR: LinguaType requires macOS 15 or newer." >&2
  exit 1
fi
for cmd in git python3 xcrun swift codesign pkgbuild; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: missing $cmd. Install Xcode / Command Line Tools first." >&2
    exit 1
  }
done

mkdir -p "$BASE/work" "$DIST"
if [[ -d "$WORK/.git" ]]; then
  echo "==> resetting pinned RIMES checkout (preserving Vendor/ cache)"
  git -C "$WORK" fetch --all --tags --prune
  git -C "$WORK" reset --hard
  # Preserve the gitignored Vendor/ directory so the Squirrel librime pkg cache
  # survives across builds. Without this, every run re-downloads ~25 MB from
  # GitHub and any transient curl error (e.g. CURLE_PARTIAL_FILE 18) aborts the
  # whole build at the very first step.
  git -C "$WORK" clean -fdx -e Vendor/
else
  echo "==> cloning RIMES"
  rm -rf "$WORK"
  git clone https://github.com/scholay/rimes.git "$WORK"
fi

git -C "$WORK" checkout --detach "$PINNED_RIMES_COMMIT"
CURRENT="$(git -C "$WORK" rev-parse HEAD)"
[[ "$CURRENT" == "$PINNED_RIMES_COMMIT" ]] || {
  echo "ERROR: pinned checkout mismatch" >&2
  exit 1
}

# Ensure the librime runtime cache is populated before build_install.sh runs.
# build_install.sh -> scripts/fetch-rime.sh checks Vendor/.cache/ for a valid
# Squirrel-1.1.2.pkg and the Octagram n-gram model before falling back to a
# fresh download; we populate them ourselves here with retry logic so flaky
# networks don't kill the build.
verify_cache_file() {
  local path="$1" expected_bytes="$2" expected_sha="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(/usr/bin/stat -f%z "$path")" == "$expected_bytes" ]] || {
    echo "  !! $label size mismatch" >&2; return 1; }
  [[ "$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')" \
      == "$expected_sha" ]] || {
    echo "  !! $label SHA-256 mismatch" >&2; return 1; }
  return 0
}
prefetch() {
  local label="$1" url="$2" path="$3" expected_bytes="$4" expected_sha="$5"
  if verify_cache_file "$path" "$expected_bytes" "$expected_sha" "$label"; then
    echo "==> reusing cached $label at $path"
    return 0
  fi
  echo "==> pre-fetching $label from $url"
  /usr/bin/curl --fail --location --show-error \
      --retry 5 --retry-delay 3 --retry-all-errors \
      --proto '=https' --tlsv1.2 \
      --output "$path" \
      "$url"
  verify_cache_file "$path" "$expected_bytes" "$expected_sha" "$label" || {
    echo "ERROR: $label cache failed size/SHA-256 verification" >&2
    exit 1
  }
}
mkdir -p "$WORK/Vendor/.cache"
prefetch "Squirrel pkg"     "$SQUIRREL_PKG_URL" "$SQUIRREL_CACHE" \
          "$SQUIRREL_PKG_BYTES" "$SQUIRREL_PKG_SHA256"
prefetch "Octagram model"   "$OCTAGRAM_MODEL_URL" "$OCTAGRAM_CACHE" \
          "$OCTAGRAM_MODEL_BYTES" "$OCTAGRAM_MODEL_SHA256"

echo "==> applying LinguaType learning/identity patch"
python3 "$BASE/patch_linguatype.py" "$WORK"

# build_install.sh refuses to run if it sees a LinguaType.app already in
# /Library/Input Methods or ~/Library/Input Methods with the same bundle ID.
# On macOS 26 we are deliberately NOT installing LinguaType.app into either
# location (TIS won't pick it up), so a leftover copy from earlier debugging
# would just block the build. Remove it before running build_install.sh.
STALE_SYSTEM_APP="/Library/Input Methods/LinguaType.app"
STALE_USER_APP="$HOME/Library/Input Methods/LinguaType.app"
for stale in "$STALE_SYSTEM_APP" "$STALE_USER_APP"; do
  if [[ -e "$stale" ]]; then
    echo "==> removing stale LinguaType.app at $stale"
    if [[ "$stale" == "/Library/Input Methods/LinguaType.app" ]]; then
      /usr/bin/sudo /bin/rm -rf "$stale"
    else
      /bin/rm -rf "$stale"
    fi
  fi
done

echo "==> building LinguaType.app payload (not installed on macOS 26)"
(
  cd "$WORK"
  ./build_install.sh release
)
# The IMK bundle is built so anyone with a Developer ID can sign + install
# it. On macOS 26 without notarized Developer ID it cannot enter TIS, so we
# do NOT copy it to ~/Library/Input Methods or /Library/Input Methods —
# leaving a half-working bundle there would just confuse future debugging.
echo "    bundle lives in $BASE/work/rimes/.build/stage/LinguaType.app"
echo "    copy it to $BASE/dist/LinguaType-0.1.0-unsigned.app if you want it"

echo "==> building LinguaTypeCompanion.app"
COMPANION_SRC="$BASE/LinguaTypeCompanion"
COMPANION_OUT="$BASE/LinguaTypeCompanion.app"
COMPANION_BIN="$COMPANION_OUT/Contents/MacOS/LinguaTypeCompanion"
rm -rf "$COMPANION_OUT"
mkdir -p "$COMPANION_OUT/Contents/MacOS" "$COMPANION_OUT/Contents/Resources"
/usr/bin/swiftc -O \
    -target arm64-apple-macos15 \
    -framework Cocoa -framework Carbon -framework Foundation -framework ApplicationServices \
    -framework SwiftUI -framework Translation -framework NaturalLanguage \
    "$COMPANION_SRC"/Sources/*.swift \
    -o "$COMPANION_BIN"
cp "$COMPANION_SRC/Resources/Info.plist" "$COMPANION_OUT/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - \
    --entitlements "$COMPANION_SRC/LinguaTypeCompanion.entitlements" \
    "$COMPANION_OUT"
/usr/bin/codesign --verify --deep --strict "$COMPANION_OUT" >/dev/null 2>&1
echo "==> LinguaTypeCompanion.app built and signed at $COMPANION_OUT"

# Install LinguaTypeCompanion.app to ~/Applications and queue a per-user
# LaunchAgent so it starts at next GUI login.
USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS"
rm -rf "$USER_APPS/LinguaTypeCompanion.app"
cp -R "$COMPANION_OUT" "$USER_APPS/LinguaTypeCompanion.app"
xattr -cr "$USER_APPS/LinguaTypeCompanion.app" 2>/dev/null || true
echo "==> installed to $USER_APPS/LinguaTypeCompanion.app"

LAUNCH_AGENT="$HOME/Library/LaunchAgents/io.linguatype.companion.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.linguatype.companion</string>
    <key>ProgramArguments</key>
    <array>
        <string>$USER_APPS/LinguaTypeCompanion.app/Contents/MacOS/LinguaTypeCompanion</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$LAUNCH_AGENT" >/dev/null
/bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null \
    || /bin/launchctl bootstrap "user/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null \
    || true
/bin/launchctl kickstart -k "gui/$(id -u)/io.linguatype.companion" 2>/dev/null || true
echo "==> LaunchAgent installed at $LAUNCH_AGENT (auto-starts at next GUI login)"

# First-run nudge: Accessibility is required for the Companion to read
# focused text. The system shows its own consent prompt the first time
# the process calls AXIsProcessTrustedWithOptions; nothing to do here
# beyond informing the user.
/usr/bin/open -g "$USER_APPS/LinguaTypeCompanion.app" 2>/dev/null || true

activation_status=0

# Bundle the LinguaTypeCompanion.app into a convenience pkg for moving the
# build to another Mac. Identifies the same way so pkgutil can recognize
# it as an upgrade path. The IMK bundle LinguaType.app is *not* packaged —
# it is only useful on macOS ≤ 25 with proper signing, which this repo
# does not currently produce.
PKGROOT="$(mktemp -d)"
trap 'rm -rf "$PKGROOT"' EXIT
mkdir -p "$PKGROOT/Applications"
cp -R "$USER_APPS/LinguaTypeCompanion.app" "$PKGROOT/Applications/LinguaTypeCompanion.app"
rm -f "$DIST/LinguaType-Companion-0.1.0-local.pkg"
pkgbuild \
  --root "$PKGROOT" \
  --identifier io.linguatype.companion.pkg \
  --version 0.1.0 \
  --install-location / \
  "$DIST/LinguaType-Companion-0.1.0-local.pkg"

cat <<EOF

============================================================
LinguaType Companion build complete (option B).

Installed app:
  $USER_APPS/LinguaTypeCompanion.app
  (also auto-started from a per-user LaunchAgent at next GUI login)

Local unsigned pkg:
  $DIST/LinguaType-Companion-0.1.0-local.pkg

Learning languages:
  French + English + Japanese

The Companion shows an A·あ item in the macOS menu bar. It reads whatever Chinese text your IME (Squirrel, SCIM ITABC,
Baidu, etc.) commits into the focused field via the Accessibility API,
then asks Apple Translation for a learning overlay.

First-run setup:
  1. Open System Settings → Privacy & Security → Accessibility.
  2. Toggle LinguaType Companion on. The OS will prompt you to authenticate.
  3. Switch to any Chinese IME (Ctrl+Space). Start typing. The floating
     learning panel should appear ~280 ms after the candidate stabilizes.

If the panel never appears:
  - Confirm the A·あ menu item is present; clicking it toggles the most recent
    panel anchored to the mouse.
  - Right-click A·あ and confirm "语言学习" is enabled.
============================================================
EOF
