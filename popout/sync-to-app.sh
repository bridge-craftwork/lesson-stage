#!/usr/bin/env bash
# Build the popout and copy the static bundle into the app's resources.
#
# Run after changing anything under popout/src. Kept as a script rather than an
# Xcode build phase for now: a build phase that shells out to npm turns every
# clean build into a node install, and the popout changes far less often than
# the Swift does.
set -euo pipefail

cd "$(dirname "$0")"

npm run build

DEST="../app/LessonStage/Popout/Resources"
mkdir -p "$DEST"
rm -f "$DEST"/*
cp dist/index.html dist/popout.js dist/popout.css "$DEST/"

echo "Copied $(ls "$DEST" | wc -l | tr -d ' ') files to $DEST"
