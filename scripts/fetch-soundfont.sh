#!/bin/sh
# ピアノ音源（FreePats「Upright Piano KW」、CC0 1.0）を取得して App/Resources/Sounds に置く。
# 大きいので git には入れない（.gitignore 済み）。要 7z（brew install p7zip）。
set -eu
cd "$(dirname "$0")/.."
DEST=App/Resources/Sounds
URL=https://freepats.zenvoid.org/Piano/UprightPianoKW/UprightPianoKW-SF2-20220221.7z
if [ -f "$DEST/UprightPianoKW.sf2" ]; then echo "already exists: $DEST/UprightPianoKW.sf2"; exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL -o "$TMP/piano.7z" "$URL"
7z x -o"$TMP/out" "$TMP/piano.7z" >/dev/null
mkdir -p "$DEST"
find "$TMP/out" -name '*.sf2' -exec cp {} "$DEST/UprightPianoKW.sf2" \;
echo "saved: $DEST/UprightPianoKW.sf2"
