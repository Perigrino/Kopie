#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Kopie"
APP="dist/Kopie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kopie"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kopie</string>
  <key>CFBundleDisplayName</key><string>Kopie</string>
  <key>CFBundleIdentifier</key><string>com.kopie.app</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>Kopie</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
ENT_FILE="$(mktemp -d)/Kopie.entitlements"
cat > "$ENT_FILE" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><false/>
</dict></plist>
ENT
echo "==> codesign"
SIGNER="${KOPIE_SIGN_IDENTITY:-}"
if [ -n "$SIGNER" ]; then
  codesign --force --sign "$SIGNER" --entitlements "$ENT_FILE" --options runtime "$APP"
else
  codesign --force --sign - --entitlements "$ENT_FILE" "$APP"
fi
rm -rf "$(dirname "$ENT_FILE")"
codesign --verify --verbose=2 "$APP"
echo "==> built $APP"
