#!/bin/bash
# Activate / manage the LinguaType Companion menu bar app.
#
# On macOS 26, TIS auto-registration of third-party input methods is silently
# dropped for ad-hoc / non-notarized bundles (VietTelex upstream confirmed via
# the same pattern: TISRegisterInputSource returns noErr but the source never
# appears in the picker). The build now produces LinguaTypeCompanion.app
# instead — a standalone menu bar app that observes focused text via the
# Accessibility API and shows translations for any Chinese IME you already
# have installed (stock SCIM ITABC, Squirrel, Baidu, …).
#
# This script manages the per-user LaunchAgent that keeps the Companion
# running across logins and offers a one-shot launch for the current shell.
#
# Usage:
#   ./activate-linguatype.sh             # install LaunchAgent + launch now
#   ./activate-linguatype.sh --schedule  # install LaunchAgent only
#   ./activate-linguatype.sh --launch    # launch the installed app now
#   ./activate-linguatype.sh --uninstall # stop LaunchAgent and remove files
#   ./activate-linguatype.sh --status    # print installation state
#
# Exit codes:
#   0  Success.
#   1  Companion.app is missing; run build-companion.sh first.
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/LinguaTypeCompanion.app"
EXE="$APP/Contents/MacOS/LinguaTypeCompanion"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/io.linguatype.companion.plist"
LABEL="io.linguatype.companion"

usage_error() {
  sed -n '2,12p' "$0"
  exit 64
}

write_launch_agent() {
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${EXE}</string>
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
}

bootstrap_agent() {
  # Remove any prior registration so a stale copy can't shadow a fresh install.
  /bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null \
    || /bin/launchctl bootstrap "user/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null \
    || true
}

launch_now() {
  if [[ ! -x "$EXE" ]]; then
    echo "ERROR: $EXE is missing. Run ./build-companion.sh first." >&2
    exit 1
  fi
  # Use launchctl so the process inherits the user's Aqua session, not a
  # Background session. Without this, AXIsProcessTrusted may behave oddly.
  /bin/launchctl asuser "$(id -u)" /usr/bin/open -g "$APP" 2>/dev/null \
    || /usr/bin/open -g "$APP" 2>/dev/null \
    || true
  echo "==> LinguaType Companion launched; check the menu bar for A·あ."
}

status() {
  echo "==> LinguaType Companion status"
  if [[ -x "$EXE" ]]; then
    echo "    installed:        $APP"
    /usr/bin/codesign --verify --deep --strict "$APP" 2>&1 | head -1 || true
  else
    echo "    installed:        NO — run ./build-companion.sh"
  fi
  if [[ -f "$LAUNCH_AGENT" ]]; then
    echo "    LaunchAgent:      $LAUNCH_AGENT"
    /bin/launchctl print "gui/$(id -u)/$LABEL" 2>&1 | head -5 || true
  else
    echo "    LaunchAgent:      not installed"
  fi
  if pgrep -x LinguaTypeCompanion >/dev/null 2>&1; then
    echo "    running:          YES (pid=$(pgrep -x LinguaTypeCompanion | head -1))"
  else
    echo "    running:          no"
  fi
}

uninstall() {
  /bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$LAUNCH_AGENT"
  pkill -x LinguaTypeCompanion 2>/dev/null || true
  echo "==> removed LaunchAgent and stopped LinguaType Companion"
  echo "    app bundle left in place at $APP — delete it manually if you want."
}

case "${1:-}" in
    --schedule) write_launch_agent; bootstrap_agent; echo "==> LaunchAgent installed; will auto-start on next GUI login."; exit 0 ;;
    --launch)   launch_now; exit 0 ;;
    --uninstall) uninstall; exit 0 ;;
    --status)   status; exit 0 ;;
    --help|-h)  usage_error ;;
    "")         ;;
    *)          usage_error ;;
esac

if [[ ! -x "$EXE" ]]; then
  echo "ERROR: $EXE is missing. Run ./build-companion.sh first." >&2
  exit 1
fi

write_launch_agent
bootstrap_agent
launch_now

cat <<DONE

==> Done.

  - LinguaType Companion is running now (menu bar: A·あ).
  - It will auto-start on every GUI login via the LaunchAgent above.
  - First-run setup: System Settings → Privacy & Security → Accessibility
    → enable "LinguaType Companion" so it can read focused text.
  - Type Chinese with any IME (Ctrl+Space). The floating learning panel
    appears ~280 ms after each commit, anchored to the caret rect.

  Manage later:
    $BASE/activate-linguatype.sh --status
    $BASE/activate-linguatype.sh --uninstall
DONE
