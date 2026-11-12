#!/bin/zsh
# Builds Derive.app (menu bar only, no Dock icon).
# ./build.sh          builds it here, in the project folder.
# ./build.sh install  builds it, then moves it to /Applications and opens it there.
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

if [[ "$1" == "install" ]]; then
    DEST=/Applications/Derive.app
    # Quit the running copy, wherever it was opened from.
    osascript -e 'tell application id "com.stephanepoulin.derive" to quit' 2>/dev/null || true
    for _ in {1..40}; do
        pgrep -f "Derive.app/Contents/MacOS/Derive" >/dev/null || break
        sleep 0.25
    done
    # Move, not copy: one copy only, so derive:// links always reach the same app.
    rm -rf "$DEST"
    mv $APP "$DEST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$PWD/$APP" 2>/dev/null || true
    open "$DEST"
    echo "Installed $DEST"
fi
