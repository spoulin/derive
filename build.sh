#!/bin/zsh
# Builds Derive.app (menu bar only, no Dock icon).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Derive.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/Derive $APP/Contents/MacOS/
# Made with tools/make-icon.swift; see the README to change it.
cp Resources/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Derive</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.stephanepoulin.derive</string>
<key>CFBundleName</key><string>Dérive</string>
<key>CFBundleDisplayName</key><string>Dérive</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>com.stephanepoulin.derive</string>
<key>CFBundleURLSchemes</key><array><string>derive</string><string>sonnov</string></array>
</dict></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
P
codesign --force --sign - $APP
echo "Built $APP"
