#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build -c debug --product Knurl >/dev/null
bin="$(swift build -c debug --show-bin-path)/Knurl"
app="$root/.build/Knurl.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Knurl"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$app" >/dev/null
else
  codesign --force --sign - "$app" >/dev/null
fi
printf '%s\n' "$app"
