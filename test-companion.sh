#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d /tmp/linguatype-companion-tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SOURCES=()
for source in "$BASE"/LinguaTypeCompanion/Sources/*.swift; do
    [[ "$(basename "$source")" == "main.swift" ]] && continue
    SOURCES+=("$source")
done

/usr/bin/swiftc -Onone \
    -framework Cocoa -framework Carbon -framework Foundation \
    -framework ApplicationServices -framework SwiftUI \
    -framework Translation -framework NaturalLanguage \
    "${SOURCES[@]}" \
    "$BASE"/LinguaTypeCompanion/Tests/*.swift \
    -o "$TMP_DIR/linguatype-companion-tests"

"$TMP_DIR/linguatype-companion-tests"
