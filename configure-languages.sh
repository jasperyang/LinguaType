#!/bin/bash
set -euo pipefail
if [[ "$#" -gt 0 ]]; then
  echo "LinguaType now always shows French, English, and Japanese together." >&2
  echo "Language arguments are no longer supported." >&2
  exit 64
fi
defaults write io.linguatype.companion LinguaType.learningEnabled -bool true
defaults write io.linguatype.companion LinguaType.dictionaryLookupEnabled -bool true
echo "LinguaType enabled: French + English + Japanese, with online word lookup."
