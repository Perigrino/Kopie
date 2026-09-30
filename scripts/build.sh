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

# App icon. The chosen design is remembered in assets/icon-sources/selected.txt
# (generate candidates with scripts/icon-sources/generate-icons-glass.swift, then set
# selected.txt to the winning design, e.g. "design10"). If Kopie.icns hasn't been
# produced yet, derive it from the selection.
if [ ! -f "assets/icon-sources/Kopie.icns" ] && [ -f "assets/icon-sources/selected.txt" ]; then
  DESIGN="$(cat assets/icon-sources/selected.txt)"
  if [ -f "assets/icon-sources/$DESIGN.icns" ]; then
    cp "assets/icon-sources/$DESIGN.icns" "assets/icon-sources/Kopie.icns"
  fi
fi
if [ -f "assets/icon-sources/Kopie.icns" ]; then
  cp "assets/icon-sources/Kopie.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
# Monochrome menu-bar glyph (scripts/icon-sources/generate-menu-template.swift)
if [ -f "assets/icon-sources/KopieMenuTemplate.png" ]; then
  cp "assets/icon-sources/KopieMenuTemplate.png" "$APP/Contents/Resources/KopieMenuTemplate.png"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kopie</string>
  <key>CFBundleDisplayName</key><string>Kopie</string>
  <key>CFBundleIdentifier</key><string>com.kopie.app</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>2.4.0</string>
  <key>CFBundleExecutable</key><string>Kopie</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Extract App Intents metadata so Shortcuts/Spotlight can discover the app's
# intents. SwiftPM doesn't run appintentsmetadataprocessor, so we do it here:
# feed the app target's object files + Swift compiler const-value files to the
# tool, which writes Metadata.appintents into the bundle's Resources.
AIP="$(xcrun -f appintentsmetadataprocessor 2>/dev/null || true)"
OBJDIR=".build/out/Intermediates.noindex/Kopie.build/$CONFIG/Kopie-p.build/Objects-normal/arm64"
if [ -n "$AIP" ] && [ -d "$OBJDIR" ]; then
  echo "==> appintentsmetadataprocessor"
  TMPDIR_AIP="$(mktemp -d)"
  find "$OBJDIR" -name '*.o' > "$TMPDIR_AIP/sources.txt"
  find "$OBJDIR" -name '*.swiftconstvalues' > "$TMPDIR_AIP/constvals.txt"
  if "$AIP" \
       --output "$APP/Contents/Resources" \
       --toolchain-dir "$(dirname "$(dirname "$(xcrun -f swift-frontend)")")" \
       --module-name Kopie \
       --sdk-root "$(xcrun --show-sdk-path)" \
       --xcode-version "$(xcodebuild -version | sed -n 's/Xcode \([0-9.]*\).*/\1/p')" \
       --platform-family macos \
       --deployment-target 13.0 \
       --target-triple "arm64-apple-macos13.0" \
       --source-file-list "$TMPDIR_AIP/sources.txt" \
       --swift-const-vals-list "$TMPDIR_AIP/constvals.txt" >/dev/null 2>&1 \
       && [ -d "$APP/Contents/Resources/Metadata.appintents" ]; then
    echo "    Metadata.appintents written"
  else
    echo "    (app intents metadata extraction skipped)"
    rm -rf "$APP/Contents/Resources/Metadata.appintents"
  fi
  rm -rf "$TMPDIR_AIP"
fi
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
  codesign --force --sign - --entitlements "$ENT_FILE" --options runtime "$APP"
fi
rm -rf "$(dirname "$ENT_FILE")"
codesign --verify --verbose=2 "$APP"
echo "==> built $APP"
