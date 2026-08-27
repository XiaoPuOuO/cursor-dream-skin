#!/bin/bash
# 将引擎部署到 ~/.cursor/cursor-dream-skin-studio（原子 rsync）。
set -Eeuo pipefail

SOURCE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SOURCE="${2:-}"; shift 2 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

MACOS_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SOURCE="${SOURCE:-$(cd "$MACOS_ROOT/.." && pwd -P)}"
INSTALL_ROOT="$HOME/.cursor/cursor-dream-skin-studio"
TMP="${INSTALL_ROOT}.staging.$$"
PREV="${INSTALL_ROOT}.previous"

for item in scripts assets presets; do
  [ -e "$SOURCE/$item" ] || { printf '引擎来源缺少: %s\n' "$item" >&2; exit 1; }
done

/bin/mkdir -p "$TMP/scripts" "$TMP/assets" "$TMP/presets"
/usr/bin/rsync -a --delete "$SOURCE/scripts/" "$TMP/scripts/"
/usr/bin/rsync -a --delete "$SOURCE/assets/" "$TMP/assets/"
/usr/bin/rsync -a --delete "$SOURCE/presets/" "$TMP/presets/"
if [ -f "$SOURCE/VERSION" ]; then
  /bin/cp "$SOURCE/VERSION" "$TMP/VERSION"
elif [ -f "$MACOS_ROOT/VERSION" ]; then
  /bin/cp "$MACOS_ROOT/VERSION" "$TMP/VERSION"
else
  printf '0.1.0\n' > "$TMP/VERSION"
fi
/bin/chmod 755 "$TMP/scripts/"*.sh 2>/dev/null || true
/bin/chmod 644 "$TMP/scripts/"*.mjs 2>/dev/null || true

/bin/rm -rf "$PREV"
[ -d "$INSTALL_ROOT" ] && /bin/mv "$INSTALL_ROOT" "$PREV"
/bin/mv "$TMP" "$INSTALL_ROOT"
/bin/rm -rf "$PREV"
printf '引擎已部署：%s\n' "$INSTALL_ROOT"
