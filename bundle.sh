#!/bin/bash
# Builds Mikkel.app so the pet can be launched from Finder and added to
# Login Items. The hook helper ships inside the bundle's MacOS directory,
# which is where HookInstaller looks for it.
set -euo pipefail

cd "$(dirname "$0")"
APP="${1:-$HOME/Applications/Mikkel.app}"

swift build -c release
BIN=".build/release"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/MikkelPet" "$APP/Contents/MacOS/MikkelPet"
cp "$BIN/mikkel-hook" "$APP/Contents/MacOS/mikkel-hook"
# SwiftPM emits the resource bundle beside the binary; the app looks it up
# through Bundle.module, so it has to travel with the executable.
cp -R "$BIN/MikkelPet_MikkelPet.bundle" "$APP/Contents/MacOS/" 2>/dev/null || \
  cp -R "$BIN"/*.bundle "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MikkelPet</string>
  <key>CFBundleIdentifier</key><string>dev.andreas.mikkel-pet</string>
  <key>CFBundleName</key><string>Mikkel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Menu bar only: no Dock tile, no app switcher entry. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signing keeps macOS from re-prompting on every launch.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Install the hooks with:"
echo "  \"$APP/Contents/MacOS/MikkelPet\" --install-hooks"
