#!/usr/bin/env bash
#
# Builds QLite.app. The result lands in build/Build/Products/<config>/QLite.app.
#
# Usage: Scripts/build.sh [Debug|Release]
set -euo pipefail

CONFIG="${1:-Release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
fi

echo "==> Generating QLite.xcodeproj"
xcodegen generate

# Hardened runtime is only usable with a real signing identity: it enables library
# validation, which an ad-hoc signed bundle cannot satisfy for its own framework.
HARDENED_RUNTIME=NO
if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    HARDENED_RUNTIME=YES
fi

echo "==> Building QLite ($CONFIG, hardened runtime: $HARDENED_RUNTIME)"
xcodebuild \
    -project QLite.xcodeproj \
    -scheme QLite \
    -configuration "$CONFIG" \
    -derivedDataPath build \
    ENABLE_HARDENED_RUNTIME="$HARDENED_RUNTIME" \
    ${DEVELOPMENT_TEAM:+DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"} \
    ${CODE_SIGN_IDENTITY:+CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"} \
    build

APP="$ROOT/build/Build/Products/$CONFIG/QLite.app"
echo "==> Built $APP"
