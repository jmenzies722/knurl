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
processor="$(xcrun --find appintentsmetadataprocessor 2>/dev/null || true)"
const_file="$(find "$root/.build" -name 'Intents.swiftconstvalues' -print -quit)"
if [[ -n "$processor" && -n "$const_file" ]]; then
  mkdir -p "$app/Contents/Resources"
  src_list="$(mktemp)"
  const_list="$(mktemp)"
  find "$root/Sources/Knurl" -name '*.swift' | sort > "$src_list"
  find "$(dirname "$const_file")" -name '*.swiftconstvalues' | sort > "$const_list"
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  toolchain="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
  xcode_ver="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3; exit}')"
  "$processor" \
    --output "$app/Contents/Resources" \
    --toolchain-dir "$toolchain" \
    --module-name Knurl \
    --sdk-root "$sdk" \
    --xcode-version "${xcode_ver:-16F6}" \
    --platform-family macOS \
    --deployment-target 26.0 \
    --target-triple arm64-apple-macosx26.0 \
    --source-file-list "$src_list" \
    --swift-const-vals-list "$const_list" \
    --force-metadata-output \
    --no-app-shortcuts-localization \
    >/dev/null 2>&1 || true
  rm -f "$src_list" "$const_list"
fi
identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$app" >/dev/null
else
  codesign --force --sign - "$app" >/dev/null
fi
printf '%s\n' "$app"
