#!/bin/bash
# Cursor Dream Skin 共用邏輯
set -Eeuo pipefail

SKIN_VERSION="0.1.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_ROOT="$HOME/.cursor-dream-skin"
STATE_PATH="$STATE_ROOT/state"
DEFAULT_CDP_PORT=9351
CURSOR_USER_DATA_DIR="$HOME/Library/Application Support/Cursor"
INJECTOR="$REPO_ROOT/scripts/injector.mjs"
ASSETS="$REPO_ROOT/assets"
THEME_DIR="$STATE_ROOT/theme"
APP_LOG="$STATE_ROOT/cursor.log"
INJECTOR_LOG="$STATE_ROOT/injector.log"
CONFIG_PATH="$STATE_ROOT/config.json"
AUTOSTART_LOG="$STATE_ROOT/autostart.log"
LAUNCH_AGENT_LABEL="com.cursor-dream-skin.autostart"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"

fail() { printf 'Cursor Dream Skin: %s\n' "$1" >&2; exit 1; }

ensure_state_root() { /bin/mkdir -p "$STATE_ROOT"; }

discover_cursor_app() {
  CURSOR_BUNDLE=""
  for candidate in "/Applications/Cursor.app" "$HOME/Applications/Cursor.app"; do
    [ -d "$candidate" ] || continue
    identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$identifier" = "com.todesktop.230313mzl4w4u92" ]; then
      CURSOR_BUNDLE="$candidate"
      break
    fi
  done
  [ -n "$CURSOR_BUNDLE" ] || fail "找不到 Cursor.app（com.todesktop.230313mzl4w4u92）。請先安裝 Cursor 或確認路徑。"
  CURSOR_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$CURSOR_BUNDLE/Contents/Info.plist")"
  export CURSOR_BUNDLE CURSOR_VERSION
}

discover_node() {
  local candidate ver
  if [ -n "${NODE_OVERRIDE:-}" ]; then
    printf '%s' "$NODE_OVERRIDE"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  for candidate in \
    "/opt/homebrew/bin/node" \
    "/usr/local/bin/node" \
    "$HOME/.nvm/current/bin/node" \
    "$HOME/.volta/bin/node" \
    "$HOME/.fnm/current/bin/node" \
    "$HOME/.local/share/mise/shims/node" \
    "$HOME/.asdf/shims/node"; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  if [ -d "$HOME/.nvm/versions/node" ]; then
    ver="$(/bin/ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | /usr/bin/sort -V | /usr/bin/tail -n 1 || true)"
    candidate="$HOME/.nvm/versions/node/${ver}/bin/node"
    if [ -n "$ver" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi
  return 1
}

require_node() {
  NODE="$(discover_node || true)"
  [ -n "$NODE" ] || fail "找不到 node。請安裝 Node.js 22+（https://nodejs.org）。"
  major="$(/usr/bin/python3 -c 'import re,sys; print(re.sub(r"^v","",sys.argv[1]).split(".")[0])' "$("$NODE" --version)")"
  [ "$major" -ge 22 ] || fail "需要 Node.js 22+ 的 WebSocket 支援，目前為 $("$NODE" --version)。"
  export NODE
}

cursor_is_running() {
  /usr/bin/pgrep -f "$CURSOR_BUNDLE/Contents/MacOS/" >/dev/null 2>&1
}

stop_cursor() {
  /usr/bin/osascript -e 'tell application "Cursor" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    cursor_is_running || return 0
    /bin/sleep 0.5
  done
  /usr/bin/pkill -f "$CURSOR_BUNDLE/Contents/MacOS/" 2>/dev/null || true
  /bin/sleep 1
  cursor_is_running && fail "Cursor 無法正常關閉，請手動結束後重試。"
}

launch_cursor_with_cdp() {
  local port="$1"
  /usr/bin/open -na "$CURSOR_BUNDLE" --args \
    --user-data-dir="$CURSOR_USER_DATA_DIR" \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$port" \
    >>"$APP_LOG" 2>&1
}

cdp_port_owner_hint() {
  local port="$1"
  if ! /usr/bin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    printf '端口 %s 無監聽进程。\n' "$port"
    return 0
  fi
  /usr/bin/lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | /usr/bin/tail -n +2 \
    | /usr/bin/awk '{printf "端口 %s 被占用: %s (pid %s)\n", "'"$port"'", $1, $2}'
  local list
  list="$(/usr/bin/curl -s --max-time 2 "http://127.0.0.1:${port}/json/list" 2>/dev/null || true)"
  if [ -n "$list" ]; then
    if /usr/bin/grep -q 'workbench\.html' <<<"$list"; then
      printf '  → 偵測到 Cursor workbench（可用）\n'
    elif /usr/bin/grep -q 'app://-/index.html' <<<"$list"; then
      printf '  → 這是 ChatGPT/Codex 的 CDP（常見於 9341），不是 Cursor。\n'
    fi
  fi
}

verified_cdp_endpoint() {
  local port="$1"
  local list
  list="$(/usr/bin/curl -s --max-time 2 "http://127.0.0.1:${port}/json/list" 2>/dev/null)" || return 1
  /usr/bin/grep -q 'workbench\.html' <<<"$list" || return 1
  return 0
}

wait_for_cdp() {
  local port="$1" deadline=$((SECONDS + 90))
  while [ $SECONDS -lt $deadline ]; do
    verified_cdp_endpoint "$port" && return 0
    /bin/sleep 0.5
  done
  return 1
}

select_available_port() {
  local port="${1:-$DEFAULT_CDP_PORT}"
  local tries=0
  while [ "$tries" -lt 32 ]; do
    if ! /usr/bin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      printf '%s' "$port"
      return 0
    fi
    if verified_cdp_endpoint "$port"; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done
  fail "找不到可用 CDP 端口（從 ${1:-$DEFAULT_CDP_PORT} 起連續 32 個都被占用）。"
}

# --- 狀態檔：port<TAB>injectorPid ---
write_state() {
  ensure_state_root
  printf '%s\t%s\n' "$1" "$2" > "$STATE_PATH"
  /bin/chmod 600 "$STATE_PATH"
}

state_field() {
  [ -f "$STATE_PATH" ] || return 1
  /usr/bin/awk -F '\t' -v n="$1" '{print $n}' "$STATE_PATH" | /usr/bin/head -n 1
}

stop_recorded_injector() {
  local pid
  pid="$(state_field 2 2>/dev/null || true)"
  [ -n "$pid" ] || return 0
  /usr/bin/pgrep -P "$pid" >/dev/null 2>&1 || /bin/kill -0 "$pid" 2>/dev/null || return 0
  /bin/kill -TERM "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6; do
    /bin/kill -0 "$pid" 2>/dev/null || return 0
    /bin/sleep 0.5
  done
  /bin/kill -KILL "$pid" 2>/dev/null || true
}

launch_injector_daemon() {
  local port="$1"
  ensure_state_root
  "$NODE" "$INJECTOR" --watch --port "$port" --theme-dir "$THEME_DIR" --timeout-ms 60000 >>"$INJECTOR_LOG" 2>&1 &
  printf '%s' "$!"
}

stage_theme() {
  # 把主題目錄同步進 STATE/theme（injector 只認這個路徑）
  local src="$1"
  ensure_state_root
  /bin/rm -rf "$THEME_DIR.tmp"
  /bin/mkdir -p "$THEME_DIR.tmp"
  /bin/cp "$src/theme.json" "$src/dream-skin.css" "$THEME_DIR.tmp/" 2>/dev/null \
    || cp "$ASSETS/theme.json" "$ASSETS/dream-skin.css" "$THEME_DIR.tmp/" 2>/dev/null || true
  # 主題自帶 CSS，否則退回 assets 的通用 CSS
  [ -s "$THEME_DIR.tmp/dream-skin.css" ] || cp "$ASSETS/dream-skin.css" "$THEME_DIR.tmp/"
  local art
  art="$(/usr/bin/python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('background','background.png'))" "$THEME_DIR.tmp/theme.json")"
  /bin/cp "$src/$art" "$THEME_DIR.tmp/$art"
  /bin/rm -rf "$THEME_DIR"
  /bin/mv "$THEME_DIR.tmp" "$THEME_DIR"
}

write_config() {
  local theme_rel="$1" port="$2" restart_existing="$3"
  ensure_state_root
  /usr/bin/python3 - "$CONFIG_PATH" "$REPO_ROOT" "$theme_rel" "$port" "$restart_existing" <<'PY'
import json, sys
path, repo, theme, port, restart = sys.argv[1:6]
cfg = {
    "repoRoot": repo,
    "theme": theme,
    "port": int(port),
    "restartExisting": restart.lower() == "true",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  /bin/chmod 600 "$CONFIG_PATH"
}

read_config_field() {
  local field="$1" fallback="${2:-}"
  [ -f "$CONFIG_PATH" ] || { printf '%s' "$fallback"; return 0; }
  /usr/bin/python3 - "$CONFIG_PATH" "$field" "$fallback" <<'PY'
import json, sys
path, field, fallback = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    val = cfg.get(field, fallback)
    print("" if val is None else val)
except Exception:
    print(fallback)
PY
}
