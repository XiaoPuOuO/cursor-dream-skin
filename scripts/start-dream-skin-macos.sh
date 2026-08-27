#!/bin/bash
# 啟動 Cursor 並注入皮膚。可重入：已注入時只做驗證。
set -Eeuo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

PORT="${DEFAULT_CDP_PORT:-9351}"
RESTART_EXISTING="false"
THEME=""
SAVE_DEFAULT="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --restart-existing) RESTART_EXISTING="true"; shift ;;
    --theme) THEME="${2:-}"; shift 2 ;;
    --save-default) SAVE_DEFAULT="true"; shift ;;
    *) fail "未知參數: $1" ;;
  esac
done
case "$PORT" in ''|*[!0-9]*) fail "無效端口: $PORT" ;; esac

ensure_state_root
discover_cursor_app
require_node

# 主題暂存：--theme 指向包含 theme.json 的目錄；已暂存過則沿用
if [ -n "$THEME" ]; then
  [ -f "$THEME/theme.json" ] || fail "主題目錄缺少 theme.json: $THEME"
  stage_theme "$THEME"
  if [ "$SAVE_DEFAULT" = "true" ]; then
    theme_rel="$(/usr/bin/python3 - "$REPO_ROOT" "$THEME" <<'PY'
import os, sys
root, theme = sys.argv[1:3]
print(os.path.relpath(os.path.abspath(theme), root))
PY
)"
    write_config "$theme_rel" "$PORT" "${RESTART_EXISTING:-false}"
    printf '已儲存預設主題：%s\n' "$theme_rel"
  fi
else
  [ -f "$THEME_DIR/theme.json" ] || stage_theme "$REPO_ROOT/presets/asuna-night"
fi

if verified_cdp_endpoint "$PORT"; then
  printf '偵測到已運行的調試端點，直接驗證/重注入…\n'
elif cursor_is_running; then
  if [ "$RESTART_EXISTING" != "true" ]; then
    fail "Cursor 正在運行但沒有皮膚端點。請執行: $0 --theme <preset> --restart-existing"
  fi
  stop_cursor
  /bin/sleep 2
  PORT="$(select_available_port "$PORT")"
  launch_cursor_with_cdp "$PORT"
  wait_for_cdp "$PORT" || {
    printf 'Cursor Dream Skin: 90 秒內 Cursor 未暴露 CDP 端點（端口 %s）。\n' "$PORT" >&2
    cdp_port_owner_hint "$PORT" >&2
    printf '提示: 9341 常被 ChatGPT/Codex 占用；本工具預設改用 %s。\n' "$DEFAULT_CDP_PORT" >&2
    printf '日誌: %s\n' "$APP_LOG" >&2
    exit 1
  }
else
  PORT="$(select_available_port "$PORT")"
  launch_cursor_with_cdp "$PORT"
  wait_for_cdp "$PORT" || {
    printf 'Cursor Dream Skin: 90 秒內 Cursor 未暴露 CDP 端點（端口 %s）。\n' "$PORT" >&2
    cdp_port_owner_hint "$PORT" >&2
    printf '日誌: %s\n' "$APP_LOG" >&2
    exit 1
  }
fi

# 先做一次帶驗證的注入；失敗即中止（fail-closed）
"$NODE" "$INJECTOR" --once --port "$PORT" --theme-dir "$THEME_DIR" --timeout-ms 60000

# 驗證通過才記錄狀態並拉起 watch 常駐（renderer 重載後自動補注入）
stop_recorded_injector
INJECTOR_PID="$(launch_injector_daemon "$PORT")"
/bin/sleep 0.5
/bin/kill -0 "$INJECTOR_PID" 2>/dev/null || fail "注入常駐进程啟動失敗，見 $INJECTOR_LOG"
write_state "$PORT" "$INJECTOR_PID"
printf 'Cursor Dream Skin %s 已生效（loopback 端口 %s）。\n' "$SKIN_VERSION" "$PORT"
