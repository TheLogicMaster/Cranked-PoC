#!/bin/bash
# Applies the patch series in patches/ to the Cranked checkout (and its submodules). Safe to run again: a patch that
# is already applied is skipped. A copy of what was applied is kept in the checkout's .git folder, so after the
# series changes (a git pull) the old patches are taken out again before the new ones go in.
# Usage: apply-patches.sh [cranked folder]
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CR=${1:-$ROOT/cranked}
[ -f "$CR/CMakeLists.txt" ] || { echo "no Cranked checkout at $CR (run scripts/fetch-cranked.sh)" >&2; exit 1; }
KEPT=$(cd "$CR" && cd "$(git rev-parse --git-dir)" && pwd)/poc-applied-patches

series() { # <folder with series>: prints "patch target" lines
  tr -d '\r' < "$1/series" | while read -r patch target; do
    [ -z "$patch" ] || [ "${patch#\#}" != "$patch" ] && continue
    echo "$patch ${target:-.}"
  done
}

# Take out an older series that differs from this one
if [ -f "$KEPT/series" ] && ! diff -rq "$KEPT" "$ROOT/patches" > /dev/null 2>&1; then
  echo "the patch series changed: taking out the one applied before"
  series "$KEPT" | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' | while read -r patch target; do
    if git -C "$CR/$target" apply --binary --check --reverse "$KEPT/$patch" 2> /dev/null; then
      git -C "$CR/$target" apply --binary --reverse "$KEPT/$patch"
      echo "removed: $patch"
    else
      echo "could not take out $patch (the files were changed since); to start again from a clean tree:" >&2
      echo "  git -C cranked reset --hard && git -C cranked clean -fd && git -C cranked submodule foreach --recursive 'git reset --hard && git clean -fd'" >&2
      echo "  (or delete cranked/ and rerun; prepare-sdk-assets.sh runs again too)" >&2
      exit 1
    fi
  done
  rm -rf "$KEPT"
fi

series "$ROOT/patches" | while read -r patch target; do
  if git -C "$CR/$target" apply --binary --check --reverse "$ROOT/patches/$patch" 2> /dev/null; then
    echo "already applied: $patch"
  else
    git -C "$CR/$target" apply --binary --whitespace=nowarn "$ROOT/patches/$patch"
    echo "applied: $patch"
  fi
done
mkdir -p "$KEPT" && cp "$ROOT/patches"/* "$KEPT/"
