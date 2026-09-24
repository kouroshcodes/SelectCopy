#!/bin/zsh
# Builds SelectCopy.app and installs it to /Applications.
set -euo pipefail
cd "${0:A:h}"

APP=build/SelectCopy.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/SelectCopy" main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SelectCopy</string>
  <key>CFBundleIdentifier</key><string>com.kourosh.selectcopy</string>
  <key>CFBundleExecutable</key><string>SelectCopy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Pin the designated requirement to the bundle ID so the Accessibility grant survives rebuilds
# (plain ad-hoc signing ties it to the binary hash, which changes every build).
codesign --force --sign - -r='designated => identifier "com.kourosh.selectcopy"' "$APP"

pkill -x SelectCopy || true
rm -rf /Applications/SelectCopy.app
cp -R "$APP" /Applications/
echo "Installed /Applications/SelectCopy.app"
