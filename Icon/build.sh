#!/usr/bin/env bash
# build.sh — composite the openHue icon and produce every deliverable.
#
#   Icon/source/artwork.png  --render.swift-->  Icon/icon-1024.png
#                                            -->  Icon/AppIcon.iconset/*.png   (sips -z)
#                                            -->  <project root>/AppIcon.icns  (iconutil)
#                                            -->  Icon/preview-512.png
#
# Usage:  Icon/build.sh            (run from anywhere)
#         ART_SCALE=1.0 Icon/build.sh   to change the crop-in (default set in render.swift)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
ART="$HERE/source/artwork.png"
MASTER="$HERE/icon-1024.png"
SET="$HERE/AppIcon.iconset"
ICNS="$ROOT/AppIcon.icns"

[[ -f "$ART" ]] || { echo "missing $ART (run generate-artwork.sh first)" >&2; exit 1; }

echo "== compositing master"
if [[ -n "${ART_SCALE:-}" ]]; then
  swift "$HERE/render.swift" "$ART" "$MASTER" --scale "$ART_SCALE"
else
  swift "$HERE/render.swift" "$ART" "$MASTER"
fi

echo "== iconset"
rm -rf "$SET"; mkdir -p "$SET"
for px in 16 32 128 256 512; do
  sips -z "$px" "$px" "$MASTER" --out "$SET/icon_${px}x${px}.png" >/dev/null
  px2=$((px * 2))
  sips -z "$px2" "$px2" "$MASTER" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
done

echo "== icns -> $ICNS"
iconutil -c icns "$SET" -o "$ICNS"

echo "== preview"
sips -z 512 512 "$MASTER" --out "$HERE/preview-512.png" >/dev/null

echo "== verify"
file "$ICNS"
TMP="$(mktemp -d)"
iconutil -c iconset "$ICNS" -o "$TMP/roundtrip.iconset"
ls "$TMP/roundtrip.iconset" | sort
rm -rf "$TMP"
echo "done"
