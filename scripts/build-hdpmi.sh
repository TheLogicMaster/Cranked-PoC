#!/bin/bash
# Builds HDPMI32.EXE, the DPMI host of the HX DOS extender (freeware, "may be used for any purpose"), from source:
# JWasm and JWlink (both built here with the host's C compiler) assemble and link it, as HX's own HDPMI32A.MAK does
# for its standard version, and the MZ header is then edited as HX's SETMZHDR tool does. The DOS build of Cranked
# needs a DPMI host; HDPMI32 is loaded first (HDPMI32 -r stays resident), or CWSDPMI.EXE is put next to CRANKED.EXE.
# Usage: build-hdpmi.sh [output folder]   (default: build/hdpmi; the result is <output>/HDPMI32.EXE)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mkdir -p "${1:-$ROOT/build/hdpmi}" && cd "${1:-$ROOT/build/hdpmi}" && pwd)
JWASM_COMMIT=7f6f32e78b79565d40bcce496756aadd1ff66900
JWLINK_COMMIT=cb7df1288619f7d3bf0290566bbe0b643fc05fd1
HX_COMMIT=f2276db9accfc57facf2588bc016a27130597bb1

fetch() { # <folder> <repository> <commit>
  [ -d "$OUT/$1/.git" ] || git clone -q "$2" "$OUT/$1"
  git -C "$OUT/$1" checkout -q "$3"
}
fetch JWasm https://github.com/Baron-von-Riedesel/JWasm $JWASM_COMMIT
fetch JWlink https://github.com/Baron-von-Riedesel/JWlink $JWLINK_COMMIT
fetch HX https://github.com/Baron-von-Riedesel/HX $HX_COMMIT

JOBS=${JOBS:-$(nproc 2> /dev/null || echo 4)}
[ -x "$OUT/JWasm/build/GccUnixR/jwasm" ] || make -C "$OUT/JWasm" -f GccUnix.mak -j "$JOBS" > "$OUT/jwasm.log" 2>&1 ||
  { tail -20 "$OUT/jwasm.log"; exit 1; }
JWASM=$OUT/JWasm/build/GccUnixR/jwasm
if [ ! -x "$OUT/JWlink/build/jwlinkLR/jwlink" ]; then
  make -C "$OUT/JWlink" -f GccUnix.mak -j "$JOBS" > "$OUT/jwlink.log" 2>&1 || { tail -20 "$OUT/jwlink.log"; exit 1; }
fi
JWLINK=$(ls "$OUT"/JWlink/build/*/jwlink | head -1)

# the sources name their include files in lower case and the files are in upper case: links in lower case for a
# case-sensitive file system
HD=$OUT/HX/Src/HDPMI
for d in "$OUT/HX/Include" "$HD"; do
  (cd "$d" && for f in *; do l=$(echo "$f" | tr A-Z a-z); [ "$l" = "$f" ] || [ -e "$l" ] || ln -s "$f" "$l"; done)
done
mkdir -p "$HD/out"
rm -f "$HD"/out/*.OBJ
MODULES=$(tr -d '\r\\' < "$HD/MODULES.INC" | sed 's/^\.//; s/^\///; s/ //g' | grep -i '\.asm$')
for m in $MODULES; do
  (cd "$HD" && "$JWASM" -nologo -c -Cp -Sg -D?32BIT=1 -D?HSINEXTMEM=0 -I../../Include -Foout/"${m%.*}".OBJ "$m") \
    > "$HD/out/${m%.*}.log" 2>&1 || { cat "$HD/out/${m%.*}.log"; exit 1; }
done
# HDPMI.OBJ first: the segment order in the executable follows it
(cd "$HD/out" && "$JWLINK" format DOS file HDPMI.OBJ file "{$(ls *.OBJ | grep -v '^HDPMI.OBJ' | tr '\n' ' ')}" \
  name HDPMI32.EXE op q, map=HDPMI32.MAP, stack=0)

# SETMZHDR: DOS loads the program only up to its stack segment (the protected mode part stays on disk until the
# host reads it), and the stack is 200h bytes
python3 - "$HD/out/HDPMI32.EXE" << 'EOF'
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, 'rb').read())
h = list(struct.unpack_from('<14H', data, 0))  # MZ header words: e_magic, e_cblp, e_cp, ..., e_ss (7), e_sp (8)
if h[8] == 0:
    h[8] = 0x200
h[5] = (h[8] + 15) >> 4           # e_minalloc: the stack's paragraphs
assert h[7], 'the stack segment in the header is zero'
paragraphs = h[7] + h[4]          # up to the stack, with the header
h[2] = (paragraphs + 31) >> 5     # e_cp: 512-byte pages
h[1] = (paragraphs & 31) << 4     # e_cblp: bytes in the last page (0 for a full one)
struct.pack_into('<14H', data, 0, *h)
open(path, 'wb').write(data)
EOF
cp "$HD/out/HDPMI32.EXE" "$OUT/HDPMI32.EXE"
echo "$OUT/HDPMI32.EXE"
