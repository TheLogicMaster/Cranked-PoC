#!/bin/bash
# Packages the CI's build artifacts as release files (the build workflow's release job runs it; it also runs on a
# folder of artifacts downloaded by hand). Usage: package-release.sh <artifacts folder> <output folder>
# The artifacts folder has one folder per artifact, named as the workflow uploads them (cranked-poc-Linux, ...).
# Builds that are missing are skipped; at least one must be there. Artifacts do not keep Unix permissions, so the
# executables get theirs back here.
set -euo pipefail
IN=$(cd "$1" && pwd)
mkdir -p "$2"
OUT=$(cd "$2" && pwd)

# zip <name> <folder> <entries...>: the entries of the folder that exist, into OUT/<name>
zipdir() {
  local name=$1 dir=$2; shift 2
  local entries=()
  for e in "$@"; do [ -e "$dir/$e" ] && entries+=("$e"); done
  [ ${#entries[@]} -gt 0 ] || return 0
  (cd "$dir" && zip -qry "$OUT/$name" "${entries[@]}")
  echo "  $name"
}

echo "release files:"
# Linux: the AppImage, and a zip of the desktop app and the libretro cores (JIT and interpreter builds)
if [ -d "$IN/cranked-poc-Linux" ]; then
  L=$IN/cranked-poc-Linux
  chmod +x "$L"/desktop*/cranked_desktop 2>/dev/null || true
  for f in "$L"/packages/*.AppImage; do
    [ -e "$f" ] || continue
    cp "$f" "$OUT/" && chmod +x "$OUT/$(basename "$f")" && echo "  $(basename "$f")"
  done
  zipdir Cranked-PoC-linux-x86_64.zip "$L" desktop desktop-nojit libretro libretro-nojit
fi
# Windows: the desktop app and the libretro cores
if [ -d "$IN/cranked-poc-Windows" ]; then
  zipdir Cranked-PoC-windows-x64.zip "$IN/cranked-poc-Windows" desktop desktop-nojit libretro libretro-nojit
fi
# macOS: the app (already zipped by the build, with its permissions), and the libretro cores
if [ -d "$IN/cranked-poc-macOS" ]; then
  M=$IN/cranked-poc-macOS
  [ -e "$M/packages/Cranked-PoC-macOS.zip" ] && cp "$M/packages/Cranked-PoC-macOS.zip" "$OUT/" && echo "  Cranked-PoC-macOS.zip"
  zipdir Cranked-PoC-macOS-libretro.zip "$M" libretro libretro-nojit
fi
# the Flatpak bundle (its artifact is named by the Flatpak action)
while IFS= read -r -d '' f; do
  cp "$f" "$OUT/Cranked-PoC-x86_64.flatpak" && echo "  Cranked-PoC-x86_64.flatpak"
  break
done < <(find "$IN" -name '*.flatpak' -print0)
# the web build, to host (see the README's "Hosting the web build")
[ -d "$IN/cranked-poc-web" ] && zipdir Cranked-PoC-web.zip "$IN/cranked-poc-web" .
# Android: the app, and the libretro core
if [ -e "$IN/cranked-poc-android/Cranked-PoC.apk" ]; then
  cp "$IN/cranked-poc-android/Cranked-PoC.apk" "$OUT/" && echo "  Cranked-PoC.apk"
fi
[ -d "$IN/cranked-poc-android-libretro" ] && zipdir Cranked-PoC-android-libretro.zip "$IN/cranked-poc-android-libretro" .
# DOS: CRANKED.EXE, the DPMI host, CRANK.BAT and README.TXT
[ -d "$IN/cranked-poc-dos" ] && zipdir Cranked-PoC-dos.zip "$IN/cranked-poc-dos" .

if [ -z "$(ls -A "$OUT")" ]; then
  echo "no build artifacts in $IN" >&2
  exit 1
fi
