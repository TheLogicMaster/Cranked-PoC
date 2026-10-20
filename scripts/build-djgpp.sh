#!/bin/bash
# Builds the DJGPP cross compiler (GCC 14.2 for 32-bit DOS) that the dos target needs, with jwt27/build-gcc at a
# fixed commit: binutils, the DJGPP C library from its CVS sources, and GCC with C and C++. It downloads the GNU
# sources, so it needs the network, and takes about half an hour on a fast machine. Cranked needs GCC 13 or later
# (<format>), so the older prebuilt DJGPP releases do not do.
# Packages it needs (Debian/Ubuntu): bison flex curl gcc g++ make texinfo zlib1g-dev tar bzip2 gzip xz-utils unzip
#   m4 dos2unix nasm patch
# Usage: build-djgpp.sh [install folder]   (default: ~/djgpp; then build.sh dos with DJGPP_PREFIX=<that folder>)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=${1:-$HOME/djgpp}
BUILD_GCC_COMMIT=9a41eab58311b0e5459757f2f0a98d2733e37a26
SRC=$ROOT/build/build-gcc
[ -d "$SRC/.git" ] || git clone -q https://github.com/jwt27/build-gcc "$SRC"
git -C "$SRC" checkout -q $BUILD_GCC_COMMIT
mkdir -p "$PREFIX"
cd "$SRC"
./build-djgpp.sh --prefix="$PREFIX" --batch binutils djgpp-cvs gcc-14.2.0
echo "DJGPP is in $PREFIX: DJGPP_PREFIX=$PREFIX scripts/build.sh dos"
