#!/usr/bin/env bash
# Builds tvOS.app, the Mac layer around the AIOStreams app in its tvOS style: the Magic Remote,
# the app switcher, Control Center and the keyboards, with no window of its own.
# Plain swiftc: the command-line tools cannot run SwiftPM, which needs Xcode's XCTest.
set -euo pipefail
cd "$(dirname "$0")"
OUT="build/tvOS.app"
# Assembled and signed in a temp folder: a synced folder adds file-system tags that codesign refuses.
WORK="$(mktemp -d)"
APP="$WORK/tvOS.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# The Mac TV app's icon, read from the system rather than kept here.
ICON="/System/Applications/TV.app/Contents/Resources/AppIcon.icns"
[ -f "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# The Jinbei Studio icon beside this file (kept out of git), which tvOS puts on the AIOStreams app.
[ -f JinbeiIcon.icns ] && cp JinbeiIcon.icns "$APP/Contents/Resources/JinbeiIcon.icns"
# Brand logos (Simple Icons) for the apps' tiles on the home.
[ -d icons ] && cp -R icons "$APP/Contents/Resources/icons"
# A profile picture beside the sources shows beside the time on the home.
for pic in profile.jpg profile.jpeg profile.png profile.webp profile.heic; do
  [ -f "$pic" ] && cp "$pic" "$APP/Contents/Resources/$pic"
done
swiftc -O -target arm64-apple-macos11 Sources/*.swift -o "$APP/Contents/MacOS/TVOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>tvOS</string>
  <key>CFBundleDisplayName</key><string>tvOS</string>
  <key>CFBundleIdentifier</key><string>com.jinbeistudio.tvhome</string>
  <key>CFBundleExecutable</key><string>TVOS</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
# One stable identity (same bundle id as before) keeps macOS's Accessibility permission across builds.
xattr -cr "$APP"
IDENTITY="tvOS Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
mkdir -p build
ditto --noextattr --noqtn "$APP" "$OUT"
rm -rf "$WORK"
# Installed in /Applications, a path that stays the same, where macOS keeps its permissions.
ditto --noextattr --noqtn "$OUT" "/Applications/tvOS.app"
# Its name for a while.
rm -rf "/Applications/Jinbei Studio.app"
echo "Built $PWD/$OUT and installed /Applications/tvOS.app"
