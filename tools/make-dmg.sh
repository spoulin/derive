#!/bin/zsh
# Makes Derive.dmg from Derive.app: the app, an Applications shortcut to drag it onto, and a
# background that says what to do the first time macOS asks about it.
# Needs dmgbuild: pip3 install dmgbuild
# Usage: tools/make-dmg.sh [Derive.app] [Derive.dmg]
set -e
cd "$(dirname "$0")/.."
APP=${1:-Derive.app}
DMG=${2:-Derive.dmg}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The background at 1x and 2x, joined into one TIFF so Retina screens get the sharp one.
swift tools/make-dmg-background.swift "$WORK/background.png" 1 >/dev/null
swift tools/make-dmg-background.swift "$WORK/background@2x.png" 2 >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" 2>/dev/null

rm -f "$DMG"
dmgbuild -s tools/dmg-settings.py -D app="$APP" -D background="$WORK/background.tiff" "Dérive" "$DMG"
echo "Made $DMG"
