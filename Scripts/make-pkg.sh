#!/usr/bin/env bash
#
# Builds a .pkg installer that copies QLite.app into /Applications and registers the
# QuickLook extensions, so previews work without launching the app first.
#
# Usage: Scripts/make-pkg.sh [version]
# Set INSTALLER_SIGN_IDENTITY to sign with a "Developer ID Installer" certificate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The generated Info.plist only holds $(MARKETING_VERSION), so read the real value from
# project.yml, which is the single source of truth for the version.
VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)}"
VERSION="${VERSION:-1.0.0}"
IDENTIFIER="com.qlite.QLite"
APP="build/Build/Products/Release/QLite.app"
STAGING="build/pkgroot"
SCRIPTS="build/pkgscripts"
DIST="dist"
PKG="$DIST/QLite-$VERSION.pkg"

if [[ ! -d "$APP" ]]; then
    echo "==> QLite.app not found, building it first"
    Scripts/build.sh Release
fi

echo "==> Staging package payload"
rm -rf "$STAGING" "$SCRIPTS" "$PKG"
mkdir -p "$STAGING" "$SCRIPTS" "$DIST"
cp -R "$APP" "$STAGING/QLite.app"

cat > "$SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
# Register the app and its QuickLook extensions with LaunchServices.
set -e
APP="/Applications/QLite.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f -R "$APP" || true
fi
/usr/bin/qlmanage -r >/dev/null 2>&1 || true
/usr/bin/qlmanage -r cache >/dev/null 2>&1 || true
exit 0
EOF
chmod +x "$SCRIPTS/postinstall"

# Without a component plist pkgbuild marks the bundle relocatable, and the installer then
# quietly updates whatever copy of QLite.app LaunchServices already knows about — including a
# build directory — instead of installing into /Applications.
COMPONENT_PLIST="build/QLite-component.plist"
pkgbuild --analyze --root "$STAGING" "$COMPONENT_PLIST" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$COMPONENT_PLIST"

echo "==> Building $PKG"
PKGBUILD_ARGS=(
    --root "$STAGING"
    --component-plist "$COMPONENT_PLIST"
    --scripts "$SCRIPTS"
    --identifier "$IDENTIFIER"
    --version "$VERSION"
    --install-location /Applications
)
if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
    PKGBUILD_ARGS+=(--sign "$INSTALLER_SIGN_IDENTITY")
else
    echo "note: building an unsigned package (set INSTALLER_SIGN_IDENTITY to sign)"
fi
pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG"

rm -rf "$STAGING" "$SCRIPTS" "$COMPONENT_PLIST"
echo "==> Wrote $PKG"
shasum -a 256 "$PKG"
