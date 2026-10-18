#!/bin/bash
# Gets Cranked at the commit the patches were made against (cranked.commit), with its submodules, into cranked/,
# and applies the patch series. Safe to run again: an existing checkout at that commit is kept (its patches are
# brought up to date). Usage: fetch-cranked.sh   (CRANKED_URL overrides where Cranked is cloned from)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CR=$ROOT/cranked
URL=${CRANKED_URL:-https://github.com/TheLogicMaster/Cranked.git}
COMMIT=$(tr -d ' \n\r' < "$ROOT/cranked.commit")

if [ ! -d "$CR/.git" ] && [ ! -f "$CR/.git" ]; then
  echo "cloning Cranked $COMMIT"
  rm -rf "$CR"
  # LF line endings whatever the platform's git default (Windows converts to CRLF, and the patches would not apply)
  git -c core.autocrlf=false -c core.eol=lf clone --no-checkout "$URL" "$CR"
  git -C "$CR" config core.autocrlf false
  git -C "$CR" checkout -q "$COMMIT"
fi
HEAD=$(git -C "$CR" rev-parse HEAD)
if [ "$HEAD" != "$COMMIT" ]; then
  echo "cranked/ is at $HEAD, not $COMMIT; remove the folder and run this again" >&2
  exit 1
fi
git -c core.autocrlf=false -C "$CR" submodule update --init --recursive
"$ROOT/scripts/apply-patches.sh" "$CR"
