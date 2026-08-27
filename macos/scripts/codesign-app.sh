#!/bin/bash
# 簽署 .app；預設自動選 Developer ID Application，否則 ad-hoc。
set -euo pipefail

sign_app_bundle() {
  local app="$1"
  local identity="${2:--}"
  local entitlements="$3"
  local exe="$app/Contents/MacOS/CursorDreamSkinMenuBar"

  if [ "$identity" = "-" ]; then
    /usr/bin/codesign --force --deep --sign - --timestamp=none "$app"
    return 0
  fi

  /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
    --entitlements "$entitlements" "$exe"
  /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime \
    --entitlements "$entitlements" "$app"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
}

pick_codesign_identity() {
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return 0
  fi
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F'"' '/Developer ID Application/ { print $2; exit }'
}

export -f sign_app_bundle pick_codesign_identity
