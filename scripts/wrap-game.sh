#!/bin/bash
# Wraps a game and the desktop front end into one thing to hand out:
#   wrap-game.sh <cranked_desktop executable> <game .pdx folder or .zip, or "none"> <output>
# The output's form follows its name:
#   *.app       a macOS app bundle (the game in Contents/Resources/game.zip)
#   *.AppImage  a Linux AppImage (needs appimagetool on the PATH)
#   anything else (e.g. MyGame or MyGame.exe): one executable file with the zipped game appended to it
# The game starts at once, without the menu bar (F1 shows it, F11 toggles fullscreen); its save data goes to the
# user's data folder (SDL's preference path, "Cranked/Proof of Concept/Data"). Only wrap games you may redistribute.
# With "none" the emulator itself is packaged (useful for the macOS app).
set -e
[ $# -eq 3 ] || { sed -n '2,10p' "$0"; exit 1; }
EXE=$1 GAME=$2 OUT=$3
[ -f "$EXE" ] || { echo "no executable at $EXE" >&2; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
# the game as a zip with the .pdx folder at its root (Cranked loads either layout)
if [ "$GAME" = none ]; then
  :
elif [ -d "$GAME" ]; then
  (cd "$(dirname "$GAME")" && python3 -m zipfile -c "$WORK/game.zip" "$(basename "$GAME")")
else
  cp "$GAME" "$WORK/game.zip"
fi
NAME=$(basename "${OUT%.*}")
case $OUT in
  *.app)
    rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
    cp "$EXE" "$OUT/Contents/MacOS/$NAME"
    [ -f "$WORK/game.zip" ] && cp "$WORK/game.zip" "$OUT/Contents/Resources/game.zip"
    cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>org.cranked.poc.$(echo "$NAME" | tr -cd 'A-Za-z0-9')</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
    command -v codesign > /dev/null && codesign --force --deep -s - "$OUT" || true # ad-hoc, so Apple silicon runs it
    ;;
  *.AppImage)
    command -v appimagetool > /dev/null || { echo "appimagetool is needed for an AppImage" >&2; exit 1; }
    D=$WORK/AppDir; mkdir -p "$D/usr/bin"
    cp "$EXE" "$D/usr/bin/cranked_desktop"
    [ -f "$WORK/game.zip" ] && cp "$WORK/game.zip" "$D/usr/bin/game.zip"
    printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/cranked_desktop" "$@"\n' > "$D/AppRun"; chmod +x "$D/AppRun"
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=cranked_desktop\nIcon=cranked\nCategories=Game;\n' "$NAME" > "$D/cranked.desktop"
    cp "$(dirname "$0")/../packaging/cranked.png" "$D/cranked.png"
    ARCH=$(uname -m) appimagetool "$D" "$OUT"
    ;;
  *)
    [ -f "$WORK/game.zip" ] || { cp "$EXE" "$OUT"; echo "copied: $OUT"; exit 0; }
    python3 - "$EXE" "$WORK/game.zip" "$OUT" <<'PY'
import sys, struct, shutil, os
exe, game, out = sys.argv[1:]
data = open(game, "rb").read()
shutil.copyfile(exe, out)
with open(out, "ab") as f:
    f.write(data + struct.pack("<Q", len(data)) + b"CRNKGAME")
os.chmod(out, 0o755)
PY
    ;;
esac
echo "wrapped: $OUT"
