#!/bin/bash
# Builds "Claude Pet.app" so the pet can be launched from Finder and added to
# Login Items. The hook helper ships inside the bundle's MacOS directory,
# which is where HookInstaller looks for it.
set -euo pipefail

cd "$(dirname "$0")"
APP="${1:-$HOME/Applications/Claude Pet.app}"

swift build -c release
BIN=".build/release"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/ClaudePet" "$APP/Contents/MacOS/claude-pet"
cp "$BIN/claude-pet-hook" "$APP/Contents/MacOS/claude-pet-hook"
# The artwork goes in Contents/Resources, where an app bundle keeps its
# resources and where a signature can seal it. It used to be copied in as
# SwiftPM's own resource bundle, which Bundle.module cannot find inside an
# .app: the installed app then fell back to reading the spritesheet out of the
# build directory, so it broke whenever the checkout moved and made macOS ask
# for access to whatever folder that was.
cp "$BIN/ClaudePet_ClaudePet.bundle/Resources/"* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>claude-pet</string>
  <key>CFBundleIdentifier</key><string>dev.andreas.claude-pet</string>
  <key>CFBundleName</key><string>Claude Pet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Menu bar only: no Dock tile, no app switcher entry. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Prefer a real signing identity over an ad-hoc one. An ad-hoc signature has no
# certificate behind it, so the app's identity is a hash of its own contents:
# change a byte, rebuild, and macOS sees an app it has never met and asks for
# every permission again. A certificate keeps the identity stable across builds.
# Falls back to ad-hoc so the script still works on a machine with no identity.
# Override with SIGN_ID, or SIGN_ID=- to force ad-hoc.
IDENTITY="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null |
  awk '/Developer ID Application|Apple Development/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  echo "Signing ad-hoc: no code signing identity found."
else
  echo "Signing with identity $IDENTITY"
fi

# Sign the executables, then the bundle around them. Not --deep: it is
# deprecated, and it was failing here on the resource bundle and taking the
# whole signature with it, silently, because the failure was thrown away. The
# app then carried only the linker's own signature.
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/claude-pet-hook"
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/claude-pet"
codesign --force --sign "$IDENTITY" --identifier dev.andreas.claude-pet "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
echo "Install the hooks with:"
echo "  \"$APP/Contents/MacOS/claude-pet\" --install-hooks"
