#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f dist/Kopie.app/Contents/MacOS/Kopie ] || { echo "run npm run build first"; exit 1; }
rm -rf dist/_dmg staging
mkdir -p staging
cp -R dist/Kopie.app staging/
ln -s /Applications staging/Applications
rm -f dist/Kopie.dmg
hdiutil create -volname "Kopie" -srcfolder staging -ov -format UDZO dist/Kopie.dmg
rm -rf staging
echo "==> dist/Kopie.dmg"
du -h dist/Kopie.dmg
