#!/bin/bash
# Copies and compiles the Playdate SDK 3.1.1 assets the patched Cranked embeds (system fonts, the CoreLibs crank
# indicator, the keyboard images and sounds) into cranked/core/resources. They are the SDK's, so they are not part of
# this repository. Usage: prepare-sdk-assets.sh [--distributable] <PlaydateSDK-3.1.1 folder> [cranked folder]
#
# --distributable (what build.sh does with SDK_ASSETS=fonts) is for builds that will be handed out: only the Playdate
# fonts (CC BY 4.0) are taken from the SDK. Every other asset, the SDK 3.1.1 ones and Cranked's own older copies in
# core/resources (crank-frames*.pdt, crank-notice-*.pdi, menu-*.pdi, bounce.pda), is replaced by a plain stand-in of
# the same name, size, frame count and audio format, drawn by make-standin-assets.py and compiled with the SDK's pdc.
# Without it, the SDK's own assets are used: such a build is for your own use only (see NOTICE.md).
set -e
MODE=full
if [ "$1" = --distributable ]; then MODE=distributable; shift; fi
SDK=${1:?usage: prepare-sdk-assets.sh [--distributable] <PlaydateSDK folder> [cranked folder]}
CR=${2:-$(dirname "$0")/../cranked}
R=$CR/core/resources
[ -x "$SDK/bin/pdc" ] || { echo "pdc not found in $SDK/bin" >&2; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/src" "$R/fonts-3.1.1" "$R/crank-3.1.1" "$R/keyboard-3.1.1"
echo 'function playdate.update() end' > "$W/src/main.lua"

# the fonts (both modes)
cp "$SDK"/CoreLibs/assets/keyboard/Roobert-24-Keyboard-Medium*.png "$SDK"/CoreLibs/assets/keyboard/*.fnt "$W/src/"
if [ $MODE = full ]; then
  cp "$SDK"/CoreLibs/assets/crank/*.png "$SDK"/CoreLibs/assets/keyboard/*.png "$SDK"/CoreLibs/assets/sfx/*.wav "$W/src/"
fi
"$SDK/bin/pdc" -q "$W/src" "$W/out.pdx"
cp "$W/out.pdx/Roobert-24-Keyboard-Medium.pft" "$R/fonts-3.1.1/"
for f in Roobert-10-Bold Roobert-11-Bold Roobert-11-Medium-extended Roobert-11-Medium Roobert-20-Medium-extended \
         Roobert-20-Medium Roobert-24-Medium; do cp "$SDK/Disk/System/Fonts/$f.pft" "$R/fonts-3.1.1/"; done

if [ $MODE = full ]; then
  for f in "$W"/out.pdx/crank-*; do cp "$f" "$R/crank-3.1.1/"; done
  for f in menu-cancel menu-del menu-ok menu-space; do cp "$W/out.pdx/$f.pdi" "$R/keyboard-3.1.1/"; done
  for f in click denial key selection selection-reverse; do [ -f "$W/out.pdx/$f.pda" ] && cp "$W/out.pdx/$f.pda" "$R/keyboard-3.1.1/"; done
  # Cranked's own copies, if an earlier --distributable run replaced them
  if [ -e "$CR/.git" ]; then
    (cd "$CR" && git checkout -q -- core/resources/crank-frames*.pdt core/resources/crank-notice-*.pdi \
      core/resources/menu-*.pdi core/resources/bounce.pda 2> /dev/null) || true
  fi
else
  # stand-ins: sources drawn from the sizes of the SDK's files (and of Cranked's copies), compiled with pdc
  python3 "$(dirname "$0")/make-standin-assets.py" "$SDK" "$R" "$W/standin" > /dev/null
  echo 'function playdate.update() end' > "$W/standin/main.lua"
  "$SDK/bin/pdc" -q "$W/standin" "$W/standin.pdx"
  rm -f "$R"/crank-3.1.1/* "$R"/keyboard-3.1.1/*
  cp "$W"/standin.pdx/crank-3.1.1/* "$R/crank-3.1.1/"
  cp "$W"/standin.pdx/keyboard-3.1.1/* "$R/keyboard-3.1.1/"
  cp "$W"/standin.pdx/upstream/* "$R/"
fi
echo $MODE > "$R/.sdk-assets"
echo "SDK assets prepared in $R ($MODE)"
