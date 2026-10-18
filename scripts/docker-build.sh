#!/bin/bash
# Builds Proof of Concept targets in Docker (docker/Dockerfile), with your Playdate SDK mounted read-only.
#   docker-build.sh --sdk <PlaydateSDK-3.1.1 folder> <target>...
# Targets are build.sh's (web, desktop, desktop-nojit, libretro, libretro-nojit, libretro-android, appimage, runner).
# The SDK must be the Linux one: its pdc compiles the system assets the build embeds (afterwards --sdk can be left out,
# until SDK_ASSETS changes). Results go to dist/ in this folder, owned by you. Environment: JOBS, ANDROID=1 (an image with the
# Android NDK, for libretro-android), IMAGE (the image name, default cranked-poc-build), SDK_ASSETS (fonts for a
# build to distribute; see build.sh).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=
ARGS=()
while [ $# -gt 0 ]; do
  case $1 in
    --sdk) SDK=$(cd "$2" && pwd); shift 2;;
    -h|--help) sed -n '2,8p' "$0"; exit 0;;
    *) ARGS+=("$1"); shift;;
  esac
done
[ ${#ARGS[@]} -gt 0 ] || { sed -n '2,8p' "$0"; exit 1; }
IMAGE=${IMAGE:-cranked-poc-build}
for t in "${ARGS[@]}"; do [ "$t" = libretro-android ] && ANDROID=1; done
if [ "${ANDROID:-0}" = 1 ]; then
  IMAGE=$IMAGE-android
  docker build -t "$IMAGE" --build-arg WITH_ANDROID=1 "$ROOT/docker"
else
  docker build -t "$IMAGE" "$ROOT/docker"
fi
MOUNTS=(-v "$ROOT:/src")
SDKARG=()
if [ -n "$SDK" ]; then
  if command -v file > /dev/null && ! file -L "$SDK/bin/pdc" 2> /dev/null | grep -q ELF; then
    echo "warning: $SDK/bin/pdc is not a Linux program; the build needs the Linux SDK" >&2
  fi
  MOUNTS+=(-v "$SDK:/sdk:ro"); SDKARG=(--sdk /sdk)
fi
TTY=(); [ -t 1 ] && TTY=(-t)
docker run --rm "${TTY[@]}" --user "$(id -u):$(id -g)" "${MOUNTS[@]}" -e JOBS -e CONFIG -e CMAKE_EXTRA -e SDK_ASSETS \
  "$IMAGE" scripts/build.sh "${SDKARG[@]}" "${ARGS[@]}"
