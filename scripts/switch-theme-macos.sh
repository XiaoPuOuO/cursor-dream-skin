#!/bin/bash
# 切换暂存主题；加 --apply 则立即套用并保存为默认。
set -Eeuo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

THEME=""
APPLY="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --theme) THEME="${2:-}"; shift 2 ;;
    --apply) APPLY="true"; shift ;;
    *) fail "未知参数: $1" ;;
  esac
done
[ -n "$THEME" ] || fail "请指定 --theme <preset 或绝对路径>"

case "$THEME" in
  /*) theme_dir="$THEME" ;;
  *) theme_dir="$REPO_ROOT/$THEME" ;;
esac
[ -f "$theme_dir/theme.json" ] || fail "主题目录缺少 theme.json: $theme_dir"

stage_theme "$theme_dir"
theme_rel="$(/usr/bin/python3 - "$REPO_ROOT" "$theme_dir" <<'PY'
import os, sys
print(os.path.relpath(os.path.abspath(sys.argv[2]), sys.argv[1]))
PY
)"
printf '已切换暂存主题：%s\n' "$theme_rel"

if [ "$APPLY" = "true" ]; then
  exec "$REPO_ROOT/scripts/start-dream-skin-macos.sh" \
    --theme "$theme_dir" --restart-existing --save-default
fi
