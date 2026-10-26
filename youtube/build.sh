#!/usr/bin/env bash
# Builds YouTube.app: the youtube-webos script (built in upstream/) inside a web view on YouTube's TV page.
# `./build.sh script` rebuilds the script first.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.local/bin:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0
if [ "${1:-}" = script ]; then
  # The script's source, youtube-webos (GPL-3.0), cloned here on first use and kept out of git.
  [ -d upstream ] || git clone --depth 1 https://github.com/webosbrew/youtube-webos upstream
  (cd upstream && pnpm install --frozen-lockfile && pnpm build)
  cp upstream/dist/webOSUserScripts/userScript.js Resources/userScript.js
fi
OUT="build/YouTube.app"
WORK="$(mktemp -d)"
APP="$WORK/YouTube.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/*.js "$APP/Contents/Resources/"
swiftc -O -target arm64-apple-macos11 Sources/*.swift -o "$APP/Contents/MacOS/YouTube"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>YouTube</string>
  <key>CFBundleDisplayName</key><string>YouTube</string>
  <key>CFBundleIdentifier</key><string>com.jinbeistudio.youtube-tv</string>
  <key>CFBundleExecutable</key><string>YouTube</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
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
# Installed in /Applications, where the tvOS Mac app (../tvos) opens it.
ditto --noextattr --noqtn "$OUT" "/Applications/YouTube.app"
echo "Built $PWD/$OUT and installed /Applications/YouTube.app"
