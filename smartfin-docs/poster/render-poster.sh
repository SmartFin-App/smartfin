#!/bin/sh
# Renders poster-a1.html to:
#   csc499-poster-SmartFin.pdf  A1 (594 x 841 mm), vector text, for printing
#   csc499-poster-SmartFin.png  A1 at 150 dpi (3508 x 4967 px), sRGB, for preview / Teams
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL="file://$PWD/poster-a1.html"
"$CHROME" --headless=new --no-pdf-header-footer --virtual-time-budget=10000 \
  --print-to-pdf=csc499-poster-SmartFin.pdf "$URL" >/dev/null 2>&1
"$CHROME" --headless=new --window-size=2245,3178 --force-device-scale-factor=1.5626 \
  --hide-scrollbars --virtual-time-budget=10000 --screenshot=csc499-poster-SmartFin.png "$URL" >/dev/null 2>&1
sips -s dpiWidth 150 -s dpiHeight 150 \
  --embedProfile "/System/Library/ColorSync/Profiles/sRGB Profile.icc" csc499-poster-SmartFin.png >/dev/null
sips -g pixelWidth -g pixelHeight -g dpiWidth csc499-poster-SmartFin.png
mdls -name kMDItemPageWidth -name kMDItemPageHeight -name kMDItemNumberOfPages csc499-poster-SmartFin.pdf 2>/dev/null || true
