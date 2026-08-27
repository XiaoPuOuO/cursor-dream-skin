#!/bin/bash
# 安裝登入時自動套用 Cursor Dream Skin（LaunchAgent）。
set -Eeuo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

THEME=""
PORT="${DEFAULT_CDP_PORT:-9351}"
RESTART_EXISTING="true"
FORCE="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --theme) THEME="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --no-restart-existing) RESTART_EXISTING="false"; shift ;;
    --force) FORCE="true"; shift ;;
    *) fail "未知參數: $1" ;;
  esac
done

if [ -z "$THEME" ]; then
  if [ -f "$CONFIG_PATH" ]; then
    THEME="$(read_config_field theme "")"
  fi
  [ -n "$THEME" ] || fail "請指定 --theme presets/asuna-starlight-glass，或先執行 start-dream-skin-macos.sh --save-default"
fi

case "$THEME" in
  /*) theme_abs="$THEME" ;;
  *) theme_abs="$REPO_ROOT/$THEME" ;;
esac
[ -f "$theme_abs/theme.json" ] || fail "主題目錄缺少 theme.json: $theme_abs"

theme_rel="$(/usr/bin/python3 - "$REPO_ROOT" "$theme_abs" <<'PY'
import os, sys
print(os.path.relpath(os.path.abspath(sys.argv[2]), sys.argv[1]))
PY
)"

ensure_state_root
write_config "$theme_rel" "$PORT" "$RESTART_EXISTING"

/bin/chmod +x "$REPO_ROOT/scripts/autostart-dream-skin-macos.sh"

if [ -f "${LAUNCH_AGENT_PLIST}" ] && [ "$FORCE" != "true" ]; then
  fail "LaunchAgent 已存在: ${LAUNCH_AGENT_PLIST} (加 --force 覆寫)"
fi

/bin/mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/plutil -create binary1 "${LAUNCH_AGENT_PLIST}"
/usr/bin/plutil -replace Label -string "$LAUNCH_AGENT_LABEL" "${LAUNCH_AGENT_PLIST}"
/usr/bin/plutil -replace RunAtLoad -bool true "${LAUNCH_AGENT_PLIST}"
/usr/bin/plutil -replace StandardOutPath -string "$AUTOSTART_LOG" "${LAUNCH_AGENT_PLIST}"
/usr/bin/plutil -replace StandardErrorPath -string "$AUTOSTART_LOG" "${LAUNCH_AGENT_PLIST}"
/usr/bin/plutil -replace ProgramArguments -json "[\"$REPO_ROOT/scripts/autostart-dream-skin-macos.sh\"]" "${LAUNCH_AGENT_PLIST}"

# 若曾載入過，先卸載再載入
/bin/launchctl bootout "gui/$(/usr/bin/id -u)" "${LAUNCH_AGENT_PLIST}" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "${LAUNCH_AGENT_PLIST}"

printf '已安裝開機自動套用。\n'
printf '  主題：%s\n' "$theme_rel"
printf '  設定：%s\n' "$CONFIG_PATH"
printf '  LaunchAgent：%s\n' "$LAUNCH_AGENT_PLIST"
printf '  日誌：%s\n' "$AUTOSTART_LOG"
printf '\n建議：在「系統設定 → 一般 → 登入項目」關閉 Cursor 的「登入時打開」，改由此腳本帶 CDP 啟動。\n'
