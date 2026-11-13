#!/bin/zsh
# Builds Derive.app (menu bar only, no Dock icon).
# ./build.sh          builds it here, in the project folder.
# ./build.sh install  builds it, then moves it to /Applications and opens it there.
#
# VERSION=1.2.0 ./build.sh  sets the version shown in the app; without it, the latest git tag
#                           (v1.2.0 gives 1.2.0), or 0.0.0 when there is none.
# UNIVERSAL=1 ./build.sh    builds for both Apple silicon and Intel Macs, as releases do.
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
VERSION=${VERSION:-0.0.0}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
if [[ -n "$UNIVERSAL" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BINARY=.build/apple/Products/Release/Derive
else
    swift build -c release
    BINARY=.build/release/Derive
fi
APP=Derive.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BINARY $APP/Contents/MacOS/
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
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>com.stephanepoulin.derive</string>
<key>CFBundleURLSchemes</key><array><string>derive</string><string>sonnov</string></array>
</dict></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
P
codesign --force --sign - $APP
echo "Built $APP $VERSION ($BUILD)"

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
