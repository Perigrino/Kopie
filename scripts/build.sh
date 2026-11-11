#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
# One place to bump a release: package.json. Info.plist is generated from it so
# the version shipped in the bundle, in the DMG name and on GitHub can never
# drift apart (it used to be copied by hand into this script).
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)"
[ -n "$VERSION" ] || { echo "error: no \"version\" in package.json" ; exit 1; }
# Sparkle compares CFBundleVersion, not the marketing string: it must be an
# integer that only ever goes up. Commit count gives that for free.
BUILD_NUMBER="${KOPIE_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)}"
# Sparkle's update feed and the base64 EdDSA public key that verifies appcasts.
# The public key is not a secret; it lives in the repo so local builds match
# shipped ones. CI may override both through the environment.
SPARKLE_FEED_URL="${KOPIE_SPARKLE_FEED_URL:-https://perigrino.github.io/Kopie/appcast.xml}"
SPARKLE_PUBLIC_KEY="${KOPIE_SPARKLE_PUBLIC_KEY:-}"
if [ -z "$SPARKLE_PUBLIC_KEY" ] && [ -f "scripts/sparkle-public-key.txt" ]; then
  SPARKLE_PUBLIC_KEY="$(tr -d '[:space:]' < scripts/sparkle-public-key.txt)"
fi
if [ -z "$SPARKLE_PUBLIC_KEY" ]; then
  echo "warning: SUPublicEDKey is empty — in-app updates will not start"
fi
echo "==> swift build -c $CONFIG ($VERSION, build $BUILD_NUMBER)"
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
# Monochrome menu-bar glyph + its "monitoring paused" slashed twin
# (scripts/icon-sources/generate-menu-icon.swift, card-stack concept).
# Both are template images — macOS tints the alpha mask to match the bar.
for RES in KopieMenuTemplate KopieMenuPaused; do
  if [ -f "assets/icon-sources/$RES.png" ]; then
    cp "assets/icon-sources/$RES.png" "$APP/Contents/Resources/$RES.png"
  fi
done
# Sparkle's MIT notice must travel with the bundled framework.
if [ -f "Resources/Sparkle-LICENSE.txt" ]; then
  cp "Resources/Sparkle-LICENSE.txt" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kopie</string>
  <key>CFBundleDisplayName</key><string>Kopie</string>
  <key>CFBundleIdentifier</key><string>com.kopie.app</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>Kopie</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><false/>
</dict></plist>
PLIST

# Sparkle ships as a SwiftPM binary artifact. SwiftPM links it but does not embed
# it in a bundle we assemble by hand, so copy the framework next to the
# executable (@executable_path/../Frameworks is on the rpath via Package.swift).
SPARKLE_FW="$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' 2>/dev/null | head -n 1)"
if [ -z "$SPARKLE_FW" ]; then
  echo "error: Sparkle.framework not found — run 'swift package resolve' first"
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

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
SIGNID="${SIGNER:--}"
TIMESTAMP=""
RUNTIME=""
if [ "$SIGNID" != "-" ]; then
  TIMESTAMP="--timestamp"
  # Hardened runtime is required for notarization, and Developer ID signing
  # gives the app and Sparkle the same Team ID so library validation passes.
  RUNTIME="--options runtime"
fi
# Ad-hoc builds deliberately skip the hardened runtime: with no Team ID,
# library validation refuses to load the embedded Sparkle.framework. The app is
# not notarizable while ad-hoc anyway, so nothing is lost.

# Sparkle first, inside-out. Its XPC services, Autoupdate tool, Updater.app and
# the framework must carry our signature before the app is sealed; otherwise
# the app's seal covers nested code signed by someone else. `preserve-metadata`
# keeps the identifiers and entitlements Sparkle ships them with (they are not
# ours to rename, and the XPC services keep their sandbox flags).
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  for HELPER in \
    "$FW/Versions/B/XPCServices/Downloader.xpc" \
    "$FW/Versions/B/XPCServices/Installer.xpc" \
    "$FW/Versions/B/Autoupdate" \
    "$FW/Versions/B/Updater.app"; do
    [ -e "$HELPER" ] || continue
    codesign --force --sign "$SIGNID" $RUNTIME \
      --preserve-metadata=identifier,entitlements $TIMESTAMP "$HELPER"
  done
  codesign --force --sign "$SIGNID" $RUNTIME \
    --preserve-metadata=identifier,entitlements $TIMESTAMP "$FW"
fi

if [ -n "$SIGNER" ]; then
  codesign --force --sign "$SIGNER" --entitlements "$ENT_FILE" --options runtime $TIMESTAMP "$APP"
else
  # Ad-hoc signing defaults the designated requirement to the code's cdhash,
  # which changes on every rebuild. macOS stores that requirement as the
  # Accessibility (TCC) grant, so every rebuild silently invalidated the grant
  # and forced a re-authorisation. Pin it to the bundle identifier instead —
  # stable across builds, so the grant survives a rebuild.
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' \
    "$APP/Contents/Info.plist" 2>/dev/null || echo com.kopie.app)"
  echo "    designated requirement: identifier \"$BUNDLE_ID\""
  codesign --force --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    --entitlements "$ENT_FILE" "$APP"
fi
rm -rf "$(dirname "$ENT_FILE")"
codesign --verify --verbose=2 "$APP"
echo "==> built $APP"
