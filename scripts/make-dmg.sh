#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f dist/Kopie.app/Contents/MacOS/Kopie ] || { echo "run npm run build first"; exit 1; }
ICON="assets/icon-sources/Kopie.icns"
[ -f "$ICON" ] || { echo "missing $ICON — run: swift scripts/icon-sources/generate-icons-glass.swift"; exit 1; }

rm -rf staging
mkdir -p staging
cp -R dist/Kopie.app staging/
ln -s /Applications staging/Applications
# Hidden volume icon — Finder displays this on the mounted volume.
cp "$ICON" staging/.VolumeIcon.icns

rm -f dist/Kopie.dmg dist/Kopie.rw.dmg
# Writable image first: we must mount it to stamp the custom-icon Finder flag.
hdiutil create -volname "Kopie" -srcfolder staging -ov -format UDRW dist/Kopie.rw.dmg

MOUNT="$(mktemp -d)"
hdiutil attach dist/Kopie.rw.dmg -mountpoint "$MOUNT" -nobrowse >/dev/null
cp "$ICON" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" >/dev/null
rm -rf "$MOUNT"

# Compress to the distributable image.
hdiutil convert dist/Kopie.rw.dmg -format UDZO -o dist/Kopie.dmg
rm -f dist/Kopie.rw.dmg
rm -rf staging

echo "==> dist/Kopie.dmg"
du -h dist/Kopie.dmg
