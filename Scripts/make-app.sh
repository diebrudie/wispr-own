#!/usr/bin/env bash
# Builds dist/WisprOwn.app — a self-contained, ad-hoc-signed menu bar app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/WisprOwn.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp .build/release/WisprOwn "$APP/Contents/MacOS/WisprOwn"
cp -R Vendor/whisper.xcframework/macos-arm64_x86_64/whisper.framework \
      "$APP/Contents/Frameworks/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.diebrudie.wisprown</string>
    <key>CFBundleName</key>
    <string>WisprOwn</string>
    <key>CFBundleExecutable</key>
    <string>WisprOwn</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>WisprOwn records your voice while you hold the dictation key, transcribes it locally, and never sends audio anywhere.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/WisprOwn"

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "First launch: right-click the app > Open (unsigned build), then grant Microphone + Accessibility."
