#!/bin/bash
# Builds Kotiki.app. Only the Command Line Tools are needed: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Kotiki.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos12.0" Sources/*.swift -o "build/tmp/kotiki-$arch"
done
lipo -create build/tmp/kotiki-arm64 build/tmp/kotiki-x86_64 -output "$APP/Contents/MacOS/kotiki"

# icon
"build/tmp/kotiki-$(uname -m)" --icon build/tmp/face.png
ICONSET=build/tmp/AppIcon.iconset && mkdir -p "$ICONSET"
sips -p 756 756 --padColor 8FA3B8 build/tmp/face.png --out build/tmp/sq.png >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s build/tmp/sq.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/tmp/sq.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kotiki</string>
  <key>CFBundleDisplayName</key><string>Kotiki</string>
  <key>CFBundleIdentifier</key><string>local.kotiki.tom-i-pirozhok</string>
  <key>CFBundleExecutable</key><string>kotiki</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP" >/dev/null 2>&1 || true
rm -rf build/tmp
echo "Done: $APP"
