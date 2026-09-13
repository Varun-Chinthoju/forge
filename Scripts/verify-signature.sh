#!/bin/bash
# Assert a built app is notarizable. Usage: ./Scripts/verify-signature.sh <path-to-.app>
set -uo pipefail

APP="${1:?usage: verify-signature.sh <path-to-.app>}"
NAME="$(basename "$APP" .app)"
STATUS=0

fail() {
    echo "✗ $1" >&2
    STATUS=1
}

# The helper is signed by its own embed phase, which is where the runtime flag goes missing.
for BIN in "$APP/Contents/MacOS/$NAME" "$APP/Contents/Helpers/ClipboardTextHelper"; do
    INFO="$(codesign -dv --verbose=2 "$BIN" 2>&1)"
    [[ "$INFO" =~ flags=0x[0-9a-f]+\([^\)]*runtime ]] ||
        fail "${BIN##*/}: hardened runtime not enabled"
done

codesign --verify --deep --strict "$APP" || fail "$NAME.app: the seal does not verify"

# Xcode injects it for Debug only; notarization refuses any build still carrying it.
ENTITLEMENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *get-task-allow* ]] && fail "$NAME.app: get-task-allow is present"

SIGNED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/tinycast-entitlements.XXXXXX")"
trap 'rm -f "$SIGNED_ENTITLEMENTS"' EXIT
if ! codesign -d --xml --entitlements - "$APP" >"$SIGNED_ENTITLEMENTS" 2>/dev/null; then
    fail "$NAME.app: could not read signed entitlements"
elif [[ "$(/usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.personal-information.calendars' \
    "$SIGNED_ENTITLEMENTS" 2>/dev/null || true)" != "true" ]]
then
    fail "$NAME.app: Calendar entitlement is missing or not true"
fi

if [ "$STATUS" -eq 0 ]; then
    echo "✓ $NAME.app is notarizable"
fi
exit "$STATUS"
