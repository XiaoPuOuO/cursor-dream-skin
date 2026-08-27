#!/bin/bash
set -euo pipefail
MACOS_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$MACOS_ROOT/VERSION")"
APP="$MACOS_ROOT/release/Cursor Dream Skin.app"
DMG="$MACOS_ROOT/release/CursorDreamSkin-v${VERSION}.dmg"
STAGING="$MACOS_ROOT/release/dmg-staging"

"$MACOS_ROOT/scripts/build-menubar-app.sh" "$@"
/bin/mkdir -p "$STAGING"
/bin/cp -R "$APP" "$STAGING/"
/bin/ln -sf /Applications "$STAGING/Applications"
/bin/rm -f "$DMG"
/usr/bin/hdiutil create -volname "Cursor Dream Skin" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
/bin/rm -rf "$STAGING"
printf 'Created %s\n' "$DMG"
