#!/bin/bash
# Assembles the hosted site: the web build, site/site.json, the games listed in site/games.tsv (downloaded into
# games/) and the games in site/links.tsv (not hosted: linked to, or downloaded through the optional proxy), with
# games.json written for the page.
# Usage: make-site.sh [--sdk-examples <PlaydateSDK folder>] <web build folder> <site folder>
# --sdk-examples also builds the SDK's example games and lists them: the Lua ones with its pdc, and the C ones for the
# device when arm-none-eabi-gcc is installed. Each example folder carries its own BSD Zero Clause license (Panic Inc.),
# which allows redistribution.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXAMPLES_SDK=
if [ "$1" = --sdk-examples ]; then EXAMPLES_SDK=$(cd "$2" && pwd); shift 2; fi
WEB=$1 OUT=$2
[ -f "$WEB/cranked.wasm" ] || { echo "no web build in $WEB (scripts/build.sh web)" >&2; exit 1; }
mkdir -p "$OUT/games"
OUT=$(cd "$OUT" && pwd) # absolute: the games are zipped from inside temporary folders
cp -R "$WEB"/. "$OUT"/
cp "$ROOT/site/site.json" "$OUT/"
EXTRA_TSV=$(mktemp)
if [ -n "$EXAMPLES_SDK" ]; then
  # playable Lua examples (Mode7Driver needs its C part, the test apps are left out)
  for ex in "Asheteroids" "FlippyFish" "Hammer Down" "Level 1-1" "2020" "DrumMachine" "MIDIPlayer" "Pathfinder" \
            "SpriteCollisionMasks"; do
    dir="$EXAMPLES_SDK/Examples/$ex"
    [ -f "$dir/Source/main.lua" ] && grep -q "BSD Zero Clause" "$dir/License.md" 2> /dev/null || continue
    name=$(echo "$ex" | tr -d ' ')
    w=$(mktemp -d)
    PLAYDATE_SDK_PATH="$EXAMPLES_SDK" "$EXAMPLES_SDK/bin/pdc" -q -sdkpath "$EXAMPLES_SDK" "$dir/Source" "$w/$name.pdx"
    cp "$dir/License.md" "$w/$name.pdx/License.md"
    (cd "$w" && python3 -m zipfile -c "$OUT/games/sdk-$name.pdx.zip" "$name.pdx")
    rm -rf "$w"
    printf 'sdk-%s.pdx.zip\tSDK %s\t%s\tPanic Inc. (Playdate SDK example)\tBSD Zero Clause (0BSD)\thttps://play.date/dev/\t-\tAn example game from the Playdate SDK\n' \
      "$name" "$(cat "$EXAMPLES_SDK/VERSION.txt" 2> /dev/null | tr -d '\n')" "$ex" >> "$EXTRA_TSV"
  done
  # the C examples, built for the device (the web build runs them on its ARM interpreter); needs arm-none-eabi-gcc
  if command -v arm-none-eabi-gcc > /dev/null; then
    for ex in "Hello World" "Life" "Particles" "Sprite Game" "Exposure" "3D library" "Tilemap" "Sprite Collisions"; do
      dir="$EXAMPLES_SDK/C_API/Examples/$ex"
      grep -q "BSD Zero Clause" "$dir/License.md" 2> /dev/null || continue
      name=$(echo "$ex" | tr -d ' ')
      w=$(mktemp -d)
      cp -R "$dir" "$w/src"
      if (cd "$w/src" && PLAYDATE_SDK_PATH="$EXAMPLES_SDK" make -s device > "$w/build.log" 2>&1); then
        pdx=$(ls -d "$w"/src/*.pdx | head -1)
        mv "$pdx" "$w/$name.pdx"
        cp "$dir/License.md" "$w/$name.pdx/License.md"
        (cd "$w" && python3 -m zipfile -c "$OUT/games/sdk-c-$name.pdx.zip" "$name.pdx")
        printf 'sdk-c-%s.pdx.zip\tSDK %s\t%s (C)\tPanic Inc. (Playdate SDK example)\tBSD Zero Clause (0BSD)\thttps://play.date/dev/\t-\tA C example from the Playdate SDK, on the ARM interpreter\n' \
          "$name" "$(cat "$EXAMPLES_SDK/VERSION.txt" 2> /dev/null | tr -d '\n')" "$ex" >> "$EXTRA_TSV"
      else
        echo "warning: left out the C example $ex (build failed; see the log below)"; tail -5 "$w/build.log"
      fi
      rm -rf "$w"
    done
  else
    echo "note: arm-none-eabi-gcc not found, so the C examples are left out"
  fi
fi
python3 - "$ROOT/site/games.tsv" "$OUT" "$EXTRA_TSV" "$ROOT/site/links.tsv" <<'PY'
import sys, json, os, urllib.request, zipfile
tsv, out, extra, links = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
games = []
for line in list(open(tsv, encoding="utf-8")) + list(open(extra, encoding="utf-8")):
    if not line.strip() or line.startswith("#"): continue
    file, version, title, author, license, source, download, description = line.rstrip("\n").split("\t")
    path = os.path.join(out, "games", file)
    try:
        if not os.path.exists(path):
            urllib.request.urlretrieve(download, path)
        zipfile.ZipFile(path).testzip()
    except Exception as e:  # an unreachable or damaged download leaves the game out, with a warning
        print("warning: left out %s: %s" % (title, e))
        if os.path.exists(path): os.remove(path)
        continue
    games.append({"title": title, "author": author, "url": "games/" + file, "version": version, "license": license,
                  "source": source, "description": description})
    print("game:", title, os.path.getsize(path), "bytes")
for line in open(links, encoding="utf-8") if os.path.exists(links) else []:
    if not line.strip() or line.startswith("#"): continue
    version, title, author, license, source, page, download, description = line.rstrip("\n").split("\t")
    g = {"title": title, "author": author, "version": version, "license": license, "source": source, "page": page,
         "description": description}
    if download != "-": g["download"] = download
    games.append(g)
    print("linked:", title)
json.dump({"title": "Games", "games": games}, open(os.path.join(out, "games.json"), "w"), indent=1)
PY
