#!/bin/zsh
# Builds "openHue.app" into ./build — a proper double-clickable macOS app bundle.
#
#   ./make-app.sh             build (release), sign, and launch
#   ./make-app.sh --no-open   build and sign only
#   ./make-app.sh --dmg       also produce build/openHue.dmg
#   BUILD_CONFIG=debug ./make-app.sh
#   SIGN_IDENTITY="Apple Development: …" ./make-app.sh
set -euo pipefail
cd "$(dirname "$0")"

OPEN=1
DMG=0
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN=0 ;;
    --dmg) DMG=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

CONFIG=${BUILD_CONFIG:-release}
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)

APP="build/openHue.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/openHue" "$APP/Contents/MacOS/openHue"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# NSBluetoothAlwaysUsageDescription is mandatory: without it macOS terminates the app the moment
# CBCentralManager is created. No LSUIElement — the app has a Dock icon and a menu bar extra.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleName</key><string>openHue</string>
    <key>CFBundleDisplayName</key><string>openHue</string>
    <key>CFBundleIdentifier</key><string>com.davidlam.openhue</string>
    <key>CFBundleExecutable</key><string>openHue</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 David Lam</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>openHue needs Bluetooth access to discover, pair with, and control your Philips Hue bulbs.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

# Signing. An Apple Development identity gives the bundle a stable designated requirement, so the
# TCC Bluetooth grant (and the bulbs' pairing) survives rebuilds. Ad-hoc signatures change with
# every build, which makes macOS re-prompt for Bluetooth access each time.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)}"
if [ -n "$IDENTITY" ]; then
  echo "Signing with: $IDENTITY"
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "No Apple Development identity found — signing ad hoc (Bluetooth permission will be re-asked after each rebuild)."
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

if [ "$DMG" = 1 ]; then
  DMG_PATH="build/openHue.dmg"
  rm -f "$DMG_PATH"
  if command -v create-dmg >/dev/null 2>&1 && create-dmg --volname "openHue" --window-size 520 320 --icon-size 100 \
      --icon "openHue.app" 130 150 --app-drop-link 390 150 "$DMG_PATH" "$APP"; then
    :
  else
    hdiutil create -volname "openHue" -srcfolder "$APP" -ov -format UDZO "$DMG_PATH"
  fi
  echo "Disk image: $DMG_PATH"
fi

if [ "$OPEN" = 1 ]; then
  pkill -x openHue 2>/dev/null || true
  open "$APP"
fi

echo "Built $APP"
