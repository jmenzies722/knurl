#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$("$root/scripts/package-app.sh")"
open "$app"
printf 'launched %s\n' "$app"
