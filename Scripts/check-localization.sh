#!/usr/bin/env bash
#
# Verifies that every translation defines exactly the same keys, so no language silently
# falls back to raw key names.
#
# Usage: Scripts/check-localization.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE="Resources/Localization/en.lproj/Localizable.strings"
status=0

keys_of() {
    plutil -convert json -o - "$1" | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))'
}

for file in Resources/Localization/*.lproj/Localizable.strings; do
    plutil -lint "$file" >/dev/null || { echo "error: $file is not a valid strings file"; status=1; continue; }
    [[ "$file" == "$BASE" ]] && continue

    missing=$(comm -23 <(keys_of "$BASE") <(keys_of "$file"))
    extra=$(comm -13 <(keys_of "$BASE") <(keys_of "$file"))

    if [[ -n "$missing" ]]; then
        echo "error: $file is missing keys:"; echo "$missing" | sed 's/^/    /'; status=1
    fi
    if [[ -n "$extra" ]]; then
        echo "error: $file has keys not present in en:"; echo "$extra" | sed 's/^/    /'; status=1
    fi
done

[[ $status -eq 0 ]] && echo "Localization files are in sync."
exit $status
