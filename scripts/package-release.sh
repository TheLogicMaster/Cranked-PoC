#!/bin/bash
# Packages the CI's build artifacts as release files (the build workflow's release job runs it; it also runs on a
# folder of artifacts downloaded by hand). Usage: package-release.sh <artifacts folder> <output folder>
# The main files are released as they are: the AppImage, the Flatpak, the Windows app, the macOS app (a zip, as an
# app is a folder) and the Android app. The rest goes in a zip for each platform ("extras": the interpreter builds,
# the libretro cores), and the web and DOS builds, which are folders, in zips of their own. The artifacts folder has
# the workflow's artifacts as download-artifact puts them: a folder for each zipped one, and the unzipped ones
# (the main files) as files, found by name wherever they are. Builds that are missing are skipped; at least one must
# be there. Zipped artifacts do not keep Unix permissions, so the executables get theirs back here.
set -euo pipefail
IN=$(cd "$1" && pwd)
mkdir -p "$2"
OUT=$(cd "$2" && pwd)

# zipdir <name> <folder> <entries...>: the entries of the folder that exist, into OUT/<name>
zipdir() {
  local name=$1 dir=$2; shift 2
  local entries=()
  [ -d "$dir" ] || return 0
  for e in "$@"; do [ -e "$dir/$e" ] && entries+=("$e"); done
  [ ${#entries[@]} -gt 0 ] || return 0
  (cd "$dir" && zip -qry "$OUT/$name" "${entries[@]}")
  echo "  $name"
}

# main <file name> [mode]: the first file of that name anywhere in the artifacts, copied as it is
main() {
  local f
  f=$(find "$IN" -type f -name "$1" -print -quit)
  [ -n "$f" ] || return 0
  cp "$f" "$OUT/$1"
  if [ -n "${2:-}" ]; then chmod "$2" "$OUT/$1"; fi
  echo "  $1"
}

echo "release files:"
main Cranked-PoC-x86_64.AppImage 755
main Cranked-PoC-windows-x64.exe
main Cranked-PoC-macOS.zip
main Cranked-PoC.apk
# the Flatpak bundle, from the Flatpak action's artifact (named by the action)
f=$(find "$IN" -type f -name '*.flatpak' -print -quit)
if [ -n "$f" ]; then cp "$f" "$OUT/Cranked-PoC-x86_64.flatpak" && echo "  Cranked-PoC-x86_64.flatpak"; fi

# the extras: the desktop app as a plain executable and as the interpreter build, and the libretro cores
L=$IN/cranked-poc-Linux
[ -d "$L" ] && { chmod +x "$L"/desktop*/cranked_desktop 2>/dev/null || true; }
zipdir Cranked-PoC-linux-x86_64-extras.zip "$L" desktop desktop-nojit libretro libretro-nojit
zipdir Cranked-PoC-windows-x64-extras.zip "$IN/cranked-poc-Windows" desktop-nojit libretro libretro-nojit
M=$IN/cranked-poc-macOS
[ -d "$M" ] && { chmod +x "$M"/desktop*/cranked_desktop 2>/dev/null || true; }
zipdir Cranked-PoC-macOS-extras.zip "$M" desktop-nojit libretro libretro-nojit

# the folders: the web build (to host), the libretro core for Android, and the DOS build
zipdir Cranked-PoC-web.zip "$IN/cranked-poc-web" .
zipdir Cranked-PoC-android-libretro.zip "$IN/cranked-poc-android-libretro" .
zipdir Cranked-PoC-dos.zip "$IN/cranked-poc-dos" .

if [ -z "$(ls -A "$OUT")" ]; then
  echo "no build artifacts in $IN" >&2
  exit 1
fi
