#!/bin/bash
# Draw the app icons (PNG) from the SVG with macOS's built-in sips. Runs on `npm install`; safe to re-run.
cd "$(dirname "$0")/../public/icons" || exit 1
for n in 32 180 192 512; do sips -s format png -z $n $n icon.svg --out icon-$n.png >/dev/null; done
for n in 180 512; do sips -s format png -z $n $n icon-square.svg --out apple-$n.png >/dev/null; done
echo "icons drawn"
