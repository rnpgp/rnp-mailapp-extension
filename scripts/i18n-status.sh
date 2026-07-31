#!/usr/bin/env bash
# i18n-status.sh
#
# Print per-locale coverage stats for Localizable.xcstrings.
# For each declared locale (other than the source language 'en'),
# prints: locale, total keys, keys with a non-stub value, coverage %.
#
# Useful for translators to see what's still missing and for CI to
# fail when coverage drops below a threshold.
#
# Usage:
#   scripts/i18n-status.sh
#   scripts/i18n-status.sh --fail-below 80   # exit non-zero if any locale < 80%

set -euo pipefail

XCSTRINGS="MailApp/MailExtensionsContainer/Resources/Localizable.xcstrings"
FAIL_BELOW=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fail-below)
            FAIL_BELOW="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -f "${XCSTRINGS}" ]]; then
    echo "ERROR: ${XCSTRINGS} not found" >&2
    exit 1
fi

python3 - "$XCSTRINGS" "$FAIL_BELOW" <<'PY'
import json
import sys
import os

path = sys.argv[1]
fail_below = float(sys.argv[2])

data = json.load(open(path, encoding="utf-8"))
strings = data.get("strings", {})

# Find every locale referenced across all keys.
locales = set()
for key, entry in strings.items():
    locs = (entry.get("localizations") or {}).keys()
    locales.update(locs)

source = data.get("sourceLanguage", "en")
locales.discard(source)
locales = sorted(locales)

if not locales:
    print("(no non-source locales declared)")
    sys.exit(0)

total_keys = len(strings)
worst = 100.0
print(f"{'locale':10} {'translated':>11} / {'total':>6}  {'coverage':>9}")
print("-" * 44)
worst_locale = ""
for loc in locales:
    translated = sum(
        1 for entry in strings.values()
        if (entry.get("localizations") or {}).get(loc, {})
           .get("stringUnit", {}).get("state") == "translated"
    )
    pct = (translated / total_keys * 100) if total_keys else 0.0
    print(f"{loc:10} {translated:>11} / {total_keys:>6}  {pct:>7.1f}%")
    if pct < worst:
        worst = pct
        worst_locale = loc

print()
if worst < fail_below:
    print(f"FAIL: {worst_locale} coverage {worst:.1f}% below threshold {fail_below:.1f}%")
    sys.exit(1)
print(f"OK: worst coverage {worst:.1f}% ({worst_locale})")
PY
