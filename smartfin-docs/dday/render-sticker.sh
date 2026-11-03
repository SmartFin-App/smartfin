#!/bin/sh
# Renders sticker.html to the CSC499 sticker spec:
# circle, 50 x 50 cm at 300 dpi (5906 px), transparent PNG, sRGB.
set -e
cd "$(dirname "$0")"
OUT=csc499-sticker-SmartFin.png
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --window-size=5906,5906 --hide-scrollbars --default-background-color=00000000 \
  --virtual-time-budget=8000 --screenshot="$OUT" "file://$PWD/sticker.html" >/dev/null 2>&1
sips -s dpiWidth 300 -s dpiHeight 300 \
  --embedProfile "/System/Library/ColorSync/Profiles/sRGB Profile.icc" "$OUT" >/dev/null
sips -g pixelWidth -g pixelHeight -g dpiWidth -g hasAlpha -g profile "$OUT"
