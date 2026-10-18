#!/bin/bash
# Packages the Linux desktop front end (after scripts/build.sh desktop): an AppImage (needs appimagetool on the PATH)
# and a Flatpak bundle (needs flatpak-builder). Usage: package-linux.sh [appimage] [flatpak]   (both by default)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXE=$ROOT/dist/desktop/cranked_desktop
[ -x "$EXE" ] || { echo "build it first: scripts/build.sh desktop" >&2; exit 1; }
WHAT=("$@"); [ ${#WHAT[@]} -gt 0 ] || WHAT=(appimage flatpak)
OUT=$ROOT/dist/packages; mkdir -p "$OUT"
for w in "${WHAT[@]}"; do
  case $w in
    appimage)
      D=$(mktemp -d)/AppDir; mkdir -p "$D/usr/bin"
      cp "$EXE" "$D/usr/bin/"
      printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/cranked_desktop" "$@"\n' > "$D/AppRun"; chmod +x "$D/AppRun"
      cp "$ROOT/packaging/org.cranked.ProofOfConcept.desktop" "$D/"
      cp "$ROOT/packaging/cranked.png" "$D/org.cranked.ProofOfConcept.png"
      ARCH=$(uname -m) appimagetool "$D" "$OUT/Cranked-PoC-$(uname -m).AppImage"
      ;;
    flatpak)
      B=$ROOT/build/flatpak
      flatpak-builder --user --install-deps-from=flathub --force-clean --repo="$B/repo" "$B/app" "$ROOT/packaging/org.cranked.ProofOfConcept.yml"
      flatpak build-bundle "$B/repo" "$OUT/Cranked-PoC.flatpak" org.cranked.ProofOfConcept
      ;;
    *) echo "unknown: $w" >&2; exit 1;;
  esac
done
ls -la "$OUT"
