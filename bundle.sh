#!/bin/sh
# Build Control.app, so Control can have its own Accessibility permission and start at login.
#
# macOS ties the permission to the app's signature. The default "-" signature changes on
# every build, so you would have to allow the permission again after each rebuild.
# To avoid that, make a code-signing certificate once in Keychain Access
# (Certificate Assistant > Create a Certificate..., type "Code Signing") and run:
#   SIGN_IDENTITY="Your Certificate Name" ./bundle.sh
set -e

swift build -c release

rm -rf Control.app
mkdir -p Control.app/Contents/MacOS Control.app/Contents/Resources
cp .build/release/Control Control.app/Contents/MacOS/Control
cp Icon/AppIcon.icns Control.app/Contents/Resources/

# LSUIElement: no Dock icon, only the menu bar item.
cat > Control.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>     <string>local.control</string>
    <key>CFBundleName</key>           <string>Control</string>
    <key>CFBundleExecutable</key>     <string>Control</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>LSMinimumSystemVersion</key> <string>14.0</string>
    <key>LSUIElement</key>            <true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" Control.app
echo "Built Control.app. Install: make install"
