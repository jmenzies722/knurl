#!/bin/zsh
# Builds, signs and installs Knurl into /Applications.
#
# This exists because of TCC. Accessibility grants — which Flow's paste and
# Window Manager both need — are recorded against an app's identity, and macOS
# gets unreliable when the same bundle identifier exists at several paths.
# Running from .build means every experiment is another copy of
# com.shualabs.knurl on disk, and a permission granted to one of them is not
# obviously the one you are now running.
#
# One copy, one place, one grant.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
built="$("$root/scripts/package-app.sh")"
target="/Applications/Knurl.app"

osascript -e 'quit app "Knurl"' 2>/dev/null || true
sleep 1

rm -rf "$target"
cp -R "$built" "$target"

# Re-sign in place so the installed copy carries the same designated
# requirement the grant is keyed to.
identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [[ -n "$identity" ]]; then
  codesign --force --deep --sign "$identity" "$target" >/dev/null 2>&1
fi

printf '%s\n' "$target"
