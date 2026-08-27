#!/bin/bash
# 公證 DMG 並 staple（需先設定 notarytool profile 或環境變數）。
# 用法:
#   xcrun notarytool store-credentials "cursor-dream-skin" \
#     --apple-id you@example.com --team-id QWY2AXYCTJ
#   ./macos/scripts/notarize-dmg.sh
set -euo pipefail

MACOS_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$MACOS_ROOT/VERSION")"
DMG="${1:-$MACOS_ROOT/release/CursorDreamSkin-v${VERSION}.dmg}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-cursor-dream-skin}"

[ -f "$DMG" ] || { printf '找不到 DMG: %s\n' "$DMG" >&2; exit 1; }

printf '提交公證: %s\n' "$DMG"
/usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

/usr/bin/xcrun stapler staple "$DMG"
APP="$MACOS_ROOT/release/Cursor Dream Skin.app"
if [ -d "$APP" ]; then
  /usr/bin/xcrun stapler staple "$APP"
fi

/usr/sbin/spctl -a -vv -t open "$DMG" 2>/dev/null || true
printf '公證完成: %s\n' "$DMG"
