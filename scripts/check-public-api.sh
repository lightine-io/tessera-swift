#!/usr/bin/env bash
# Public-API guard for the TesseraUI SwiftUI product.
#
# TesseraUI's public surface FREEZES at the 0.5.0 tag under ADR-007. This guard makes any change to that
# surface — additions, removals, or signature changes — a deliberate, reviewed act: it dumps the module's
# current API with swift-api-digester and diffs it against the committed baseline. A full-dump diff (rather
# than swift-api-digester's -diagnose-sdk breakage report) is used on purpose: -diagnose-sdk reports only
# BREAKING changes and silently ignores additions, but a frozen surface must catch an accidental new public
# symbol too. Any difference fails CI.
#
#   ./scripts/check-public-api.sh            # verify current API == baseline (CI mode)
#   ./scripts/check-public-api.sh --update   # regenerate the baseline after an intentional surface change
#
# Regenerating the baseline is how you ACCEPT a surface change; the diff in review shows exactly what moved.
set -euo pipefail

MODULE="TesseraUI"
SCHEME="TesseraUI"
TARGET_TRIPLE="arm64-apple-ios18.0-simulator"       # matches Package.swift .iOS(.v18)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$REPO_ROOT/api/$MODULE.baseline.json"
DDP="${API_GUARD_DERIVED_DATA:-$REPO_ROOT/.build-apiguard}"
PRODUCTS="$DDP/Build/Products/Debug-iphonesimulator"
CURRENT="$(mktemp -t "$MODULE.current.XXXXXX.json")"

# Strip the machine-specific -I/-F search paths swift-api-digester echoes into the dump, so the baseline is
# portable across machines/CI. The paths appear as JSON string values (with escaped slashes) containing
# "Debug-iphonesimulator"; replace each such quoted value wholesale. The API structure carries no paths.
# Two machine/run-specific tokens the digester echoes into the dump's tool-args tail: the -I/-F products
# search paths, and the -o temp output filename (a fresh mktemp name each run). Neutralize both.
normalize() {
  sed -E \
    -e 's#"[^"]*Debug-iphonesimulator[^"]*"#"PRODUCTS"#g' \
    -e 's#"[^"]*'"$MODULE"'\.current[^"]*"#"OUTPUT"#g' \
    "$1"
}

echo "==> Building $SCHEME for iOS Simulator (clean, into $DDP)"
rm -rf "$DDP"
xcodebuild build \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DDP" \
  -skipPackagePluginValidation \
  -quiet

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
echo "==> Dumping $MODULE public API"
xcrun --sdk iphonesimulator swift-api-digester -dump-sdk \
  -module "$MODULE" \
  -o "$CURRENT" \
  -I "$PRODUCTS" -F "$PRODUCTS" -F "$PRODUCTS/PackageFrameworks" \
  -target "$TARGET_TRIPLE" -sdk "$SDK" \
  -abort-on-module-fail

if [[ "${1:-}" == "--update" ]]; then
  normalize "$CURRENT" > "$BASELINE"
  echo "==> Baseline regenerated: $BASELINE"
  exit 0
fi

if [[ ! -f "$BASELINE" ]]; then
  echo "ERROR: no baseline at $BASELINE. Create it with: $0 --update" >&2
  exit 1
fi

if diff -u <(normalize "$BASELINE") <(normalize "$CURRENT") > /tmp/tesseraui-api.diff; then
  echo "==> OK: TesseraUI public API matches the frozen baseline."
else
  echo "ERROR: TesseraUI public API differs from the frozen baseline (ADR-007)." >&2
  echo "       If the change is intentional, review the diff and run: $0 --update" >&2
  echo "----------------------------------------------------------------------" >&2
  cat /tmp/tesseraui-api.diff >&2
  exit 1
fi
