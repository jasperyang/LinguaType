#!/bin/bash
set -euo pipefail
DOMAIN="io.linguatype.inputmethod"
PRIMARY="${1:-fr}"
SECONDARY="${2:-en}"
defaults write "$DOMAIN" LinguaType.primaryLanguage "$PRIMARY"
defaults write "$DOMAIN" LinguaType.secondaryLanguage "$SECONDARY"
defaults write "$DOMAIN" LinguaType.learningEnabled -bool true
echo "LinguaType languages: primary=$PRIMARY secondary=$SECONDARY"
echo "Switch away from LinguaType and back once for the change to take effect."
