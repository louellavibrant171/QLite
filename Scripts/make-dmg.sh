#!/usr/bin/env bash
#
# Builds a drag-and-drop DMG installer: QLite.app next to an /Applications symlink.
#
# Usage: Scripts/make-dmg.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The generated Info.plist only holds $(MARKETING_VERSION), so read the real value from
# project.yml, which is the single source of truth for the version.
VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)}"
VERSION="${VERSION:-1.0.0}"
APP="build/Build/Products/Release/QLite.app"
STAGING="build/dmg"
DIST="dist"
DMG="$DIST/QLite-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
    echo "==> QLite.app not found, building it first"
    Scripts/build.sh Release
fi

echo "==> Staging disk image contents"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING" "$DIST"
cp -R "$APP" "$STAGING/QLite.app"
ln -s /Applications "$STAGING/Applications"

# A short README inside the image explains the QuickLook step to first-time users.
cat > "$STAGING/READ ME.txt" <<'EOF'
QLite — SQLite browser for macOS

1. Drag QLite.app onto the Applications folder.
2. Launch QLite once. This registers the QuickLook preview and thumbnail
   extensions, after which pressing Space on any .sqlite/.db file in Finder
   shows its tables, structure and sample rows.

QuickLook not updating? Run this in Terminal:
    qlmanage -r && qlmanage -r cache && killall Finder
EOF

echo "==> Creating $DMG"
hdiutil create \
    -volname "QLite $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"
echo "==> Wrote $DMG"
shasum -a 256 "$DMG"
