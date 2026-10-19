#!/bin/bash
# Builds Proof of Concept targets from the patched Cranked checkout.
#
# Usage: build.sh [--sdk <PlaydateSDK-3.1.1 folder>] <target>...
# Targets:
#   web             the browser front end (Emscripten; set EMSDK or have emcc on PATH)
#   desktop         the SDL desktop front end, with Unicorn's JIT
#   desktop-nojit   the desktop front end with the ARM interpreter (no JIT; for platforms that forbid it)
#   libretro        the libretro core, with Unicorn's JIT
#   libretro-nojit  the libretro core with the ARM interpreter
#   libretro-android  the libretro core for Android, interpreter (ANDROID_NDK_HOME; ANDROID_ABI, default arm64-v8a)
#   android         the Android app, an APK (interpreter; ANDROID_NDK_HOME (r26+), ANDROID_HOME, Gradle 8.9+, JDK 17;
#                   ANDROID_ABIS, default arm64-v8a; GRADLE, default gradle)
#   appimage        a Linux AppImage of the desktop front end (builds desktop first; needs appimagetool)
#   runner          the headless test runner
# Results go to dist/<target>/. Build folders are build/<target>/. Environment: CONFIG (Release), JOBS, CMAKE_EXTRA.
# The SDK is needed once, for its assets (see prepare-sdk-assets.sh); PLAYDATE_SDK_PATH works too.
# SDK_ASSETS=fonts makes a build to distribute: only the Playdate fonts (CC BY 4.0) come from the SDK and its other
# assets are replaced by plain stand-ins (prepare-sdk-assets.sh --distributable). Without it the SDK's own assets are
# embedded, and the build is for your own use only (see NOTICE.md). Changing it prepares the assets again.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CR=$ROOT/cranked
SDK=${PLAYDATE_SDK_PATH:-}
TARGETS=()
while [ $# -gt 0 ]; do
  case $1 in
    --sdk) SDK=$2; shift 2;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) TARGETS+=("$1"); shift;;
  esac
done
[ ${#TARGETS[@]} -gt 0 ] || { sed -n '2,20p' "$0"; exit 1; }

JOBS=${JOBS:-$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 4)}
GEN=(); command -v ninja > /dev/null && GEN=(-G Ninja)
CONFIG=${CONFIG:-Release}

# 1. sources: Cranked at the pinned commit with the patches applied (fetch-cranked.sh), SDK assets
"$ROOT/scripts/fetch-cranked.sh"
case ${SDK_ASSETS:-all} in
  fonts) WANT=distributable; PREP=(--distributable);;
  all) WANT=full; PREP=();;
  *) echo "SDK_ASSETS is fonts or all" >&2; exit 1;;
esac
HAVE=$(cat "$CR/core/resources/.sdk-assets" 2> /dev/null || true)
# assets prepared before the mode was recorded are the SDK's own
[ -z "$HAVE" ] && [ -f "$CR/core/resources/fonts-3.1.1/Roobert-11-Medium.pft" ] && HAVE=full
if [ "$HAVE" != "$WANT" ]; then
  [ -n "$SDK" ] || { echo "the Playdate SDK 3.1.1 is needed once for its assets: build.sh --sdk <folder> ..." >&2; exit 1; }
  "$ROOT/scripts/prepare-sdk-assets.sh" "${PREP[@]}" "$SDK" "$CR"
fi

COMMON=(-DCMAKE_BUILD_TYPE=$CONFIG -DSKIP_TESTING=ON -DSKIP_JAVA=ON -DUSE_TRACY=OFF)
# extra CMake options from the environment, e.g. CMAKE_EXTRA="-DCPM_asio_SOURCE=/path/to/asio" when offline
read -r -a EXTRA <<< "${CMAKE_EXTRA:-}"
COMMON+=("${EXTRA[@]}")
# Windows has no system zlib (libzip needs one): build the copy Cranked bundles, statically, once
windows_zlib() {
  local src=$CR/core/libs/zlib out=$ROOT/build/zlib-windows
  if [ ! -f "$out/install/include/zlib.h" ]; then
    cmake -S "$src" -B "$out/build" "${GEN[@]}" -DCMAKE_BUILD_TYPE=$CONFIG -DCMAKE_INSTALL_PREFIX="$out/install" \
      -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_EXAMPLES=OFF
    cmake --build "$out/build" --config $CONFIG -j "$JOBS"
    cmake --install "$out/build" --config $CONFIG
  fi
  local lib; lib=$(ls "$out"/install/lib/*.lib "$out"/install/lib/*.a 2> /dev/null | head -1)
  [ -n "$lib" ] || { echo "zlib did not build" >&2; exit 1; }
  COMMON+=(-DZLIB_LIBRARY="$lib" -DZLIB_INCLUDE_DIR="$out/install/include")
}
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) windows_zlib;; esac

android_ndk() { # sets NDK: ANDROID_NDK_HOME, else the newest NDK in the SDK's ndk/ folder; r26 or later
  NDK=${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}
  if [ -z "$NDK" ] && [ -d "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/ndk" ]; then
    NDK=$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/ndk/*/ 2> /dev/null | sort -V | tail -1); NDK=${NDK%/}
  fi
  [ -f "$NDK/build/cmake/android.toolchain.cmake" ] || { echo "the Android NDK is needed (ANDROID_NDK_HOME)" >&2; exit 1; }
  # older NDKs' C++ library lacks <format> and C++20 string conversions the code uses
  local major; major=$(sed -n 's/^Pkg.Revision *= *\([0-9]*\).*/\1/p' "$NDK/source.properties" 2> /dev/null)
  if [ -n "$major" ] && [ "$major" -lt 26 ]; then
    echo "the Android NDK in $NDK is version $major; r26 or later is needed (the CI and Docker builds use r27)" >&2
    exit 1
  fi
}
native() { # <target> <cmake target> <extra options...>
  local t=$1 ct=$2; shift 2
  cmake -S "$CR" -B "$ROOT/build/$t" "${GEN[@]}" "${COMMON[@]}" "$@"
  cmake --build "$ROOT/build/$t" --target "$ct" --config $CONFIG -j "$JOBS"
}
collect() { # <target> <files...>: copies the built files (any that exist) to dist/<target>
  local t=$1; shift
  mkdir -p "$ROOT/dist/$t"
  for f in "$@"; do for g in $f; do [ -e "$g" ] && cp -R "$g" "$ROOT/dist/$t/"; done; done
  echo "dist/$t:"; ls "$ROOT/dist/$t"
}

emscripten_zlib() { # zlib for libzip, built with emcc from the copy Cranked bundles
  local out=$ROOT/build/wasm-zlib
  [ -f "$out/libz.a" ] && return
  mkdir -p "$out/include"
  for f in adler32 compress crc32 deflate gzclose gzlib gzread gzwrite infback inffast inflate inftrees trees uncompr zutil; do
    emcc -O2 -DHAVE_UNISTD_H -DHAVE_STDARG_H -c "$CR/core/libs/zlib/$f.c" -o "$out/$f.o"
  done
  emar rcs "$out/libz.a" "$out"/*.o
  cp "$CR/core/libs/zlib/zlib.h" "$CR/core/libs/zlib/zconf.h" "$out/include/"
}

for t in "${TARGETS[@]}"; do
  case $t in
    web)
      if ! command -v emcc > /dev/null && [ -n "$EMSDK" ]; then source "$EMSDK/emsdk_env.sh" > /dev/null; fi
      command -v emcc > /dev/null || { echo "emcc not found (Emscripten 3.1.52 or later)" >&2; exit 1; }
      emscripten_zlib
      FLAGS="-fwasm-exceptions -flto"
      emcmake cmake -S "$CR" -B "$ROOT/build/web" "${GEN[@]}" "${COMMON[@]}" -DUSE_UNICORN=OFF -DUSE_INTERPRETER=ON \
        -DUSE_SOCKETS=OFF -DUSE_CAPSTONE=OFF -DSKIP_DESKTOP=ON -DSKIP_LIBRETRO=ON \
        -DZLIB_LIBRARY="$ROOT/build/wasm-zlib/libz.a" -DZLIB_INCLUDE_DIR="$ROOT/build/wasm-zlib/include" \
        "-DCMAKE_CXX_FLAGS=$FLAGS" "-DCMAKE_C_FLAGS=$FLAGS" "-DCMAKE_EXE_LINKER_FLAGS=$FLAGS"
      cmake --build "$ROOT/build/web" --target cranked_web -j "$JOBS"
      collect web "$ROOT/build/web/web/*.html" "$ROOT/build/web/web/*.js" "$ROOT/build/web/web/*.wasm" \
        "$ROOT/build/web/web/*.webmanifest" "$ROOT/build/web/web/*.png"
      ;;
    desktop|desktop-nojit)
      if [ $t = desktop ]; then E=(-DUSE_UNICORN=ON); else E=(-DUSE_UNICORN=OFF -DUSE_INTERPRETER=ON); fi
      native $t cranked_desktop "${E[@]}" -DSKIP_DESKTOP=OFF -DSKIP_LIBRETRO=ON
      collect $t "$ROOT/build/$t/desktop/cranked_desktop" "$ROOT/build/$t/desktop/$CONFIG/cranked_desktop.exe" \
        "$ROOT/build/$t/desktop/cranked_desktop.exe" "$ROOT/build/$t/desktop/cranked_desktop.app" \
        "$ROOT/build/$t/desktop/$CONFIG/*.dll" "$ROOT/build/$t/desktop/*.dll"
      ;;
    libretro|libretro-nojit)
      if [ $t = libretro ]; then E=(-DUSE_UNICORN=ON); else E=(-DUSE_UNICORN=OFF -DUSE_INTERPRETER=ON); fi
      native $t cranked_libretro "${E[@]}" -DSKIP_DESKTOP=ON -DSKIP_LIBRETRO=OFF
      collect $t "$ROOT/build/$t/libretro/*cranked_libretro*" "$ROOT/build/$t/libretro/$CONFIG/*cranked_libretro*" "$ROOT/packaging/cranked_libretro.info"
      ;;
    libretro-android)
      android_ndk
      native $t cranked_libretro -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=${ANDROID_ABI:-arm64-v8a} -DANDROID_PLATFORM=android-24 -DUSE_UNICORN=OFF -DUSE_INTERPRETER=ON \
        -DUSE_SOCKETS=OFF -DUSE_CAPSTONE=OFF -DSKIP_DESKTOP=ON -DSKIP_LIBRETRO=OFF
      collect $t "$ROOT/build/$t/libretro/*cranked_libretro*" "$ROOT/packaging/cranked_libretro.info"
      ;;
    android)
      android_ndk
      # the JNI library (Cranked's java/ binding) for each ABI, with the interpreter as in the libretro core for
      # Android, then the app around it (android/)
      JNILIBS=$ROOT/android/app/src/main/jniLibs
      rm -rf "$JNILIBS"
      for abi in ${ANDROID_ABIS:-arm64-v8a}; do
        native android-$abi cranked_java -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
          -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-24 -DUSE_UNICORN=OFF -DUSE_INTERPRETER=ON \
          -DUSE_SOCKETS=OFF -DUSE_CAPSTONE=OFF -DSKIP_JAVA=OFF -DSKIP_DESKTOP=ON -DSKIP_LIBRETRO=ON
        mkdir -p "$JNILIBS/$abi"
        cp "$ROOT/build/android-$abi/java/libcranked_java.so" "$JNILIBS/$abi/"
        "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip "$JNILIBS/$abi/libcranked_java.so"
      done
      (cd "$ROOT/android" && ${GRADLE:-gradle} --no-daemon assembleRelease)
      mkdir -p "$ROOT/dist/android"
      cp "$ROOT/android/app/build/outputs/apk/release/app-release.apk" "$ROOT/dist/android/Cranked-PoC.apk"
      echo "dist/android:"; ls "$ROOT/dist/android"
      ;;
    appimage)
      [ -x "$ROOT/dist/desktop/cranked_desktop" ] || "$0" desktop
      "$ROOT/scripts/package-linux.sh" appimage
      ;;
    runner)
      native runner cranked_runner -DUSE_UNICORN=ON -DSKIP_DESKTOP=ON -DSKIP_LIBRETRO=ON
      collect runner "$ROOT/build/runner/runner/cranked_runner" "$ROOT/build/runner/runner/$CONFIG/cranked_runner.exe"
      ;;
    *) echo "unknown target: $t" >&2; exit 1;;
  esac
done
