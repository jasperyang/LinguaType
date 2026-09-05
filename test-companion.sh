#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d /tmp/linguatype-companion-tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

/usr/bin/swiftc -Onone \
    -framework Cocoa -framework Carbon -framework Foundation \
    -framework ApplicationServices -framework SwiftUI \
    -framework Translation -framework NaturalLanguage \
    "$BASE/LinguaTypeCompanion/Sources/AppDelegate.swift" \
    "$BASE/LinguaTypeCompanion/Sources/LearningCoordinator.swift" \
    "$BASE/LinguaTypeCompanion/Sources/Preferences.swift" \
    "$BASE/LinguaTypeCompanion/Sources/StatusBarController.swift" \
    "$BASE/LinguaTypeCompanion/Sources/TranslationObserver.swift" \
    "$BASE/LinguaTypeCompanion/Sources/TranslationPanel.swift" \
    "$BASE/LinguaTypeCompanion/Sources/WindowGeometry.swift" \
    "$BASE/LinguaTypeCompanion/Tests/CompanionRegressionTests.swift" \
    -o "$TMP_DIR/linguatype-companion-tests"

"$TMP_DIR/linguatype-companion-tests"
