#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="发票PDF合并"
EXECUTABLE_NAME="InvoicePDFMerger"
BUNDLE_ID="com.local.invoice-pdf-merger"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/invoice-pdf-merger.XXXXXX")"
BUILD_DIR="$STAGE_DIR/build"
APP_DIR="$STAGE_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
DMG_ROOT="$BUILD_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_DISPLAY_NAME.dmg"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$DMG_ROOT"

swift build -c release

cp ".build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

sips -z 16 16 assets/app-icon.png --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 assets/app-icon.png --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 assets/app-icon.png --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 assets/app-icon.png --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 assets/app-icon.png --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 assets/app-icon.png --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 assets/app-icon.png --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 assets/app-icon.png --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 assets/app-icon.png --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 assets/app-icon.png --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR" >/dev/null
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

cp -R "$APP_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "DMG: $DMG_PATH"
