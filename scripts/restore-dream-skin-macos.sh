#!/bin/bash
# 一鍵還原：停常駐、請 renderer 自我清理，再正常重啟 Cursor。
set -Eeuo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

KEEP_RUNNING="false"
[ "${1:-}" = "--keep-running" ] && KEEP_RUNNING="true"

ensure_state_root
discover_cursor_app
require_node

PORT="$(state_field 1 2>/dev/null || true)"

if [ -n "$PORT" ] && verified_cdp_endpoint "$PORT"; then
  # 讓注入器自己在 renderer 內 cleanup（移除 style/wallpaper/attribute）
  "$NODE" - "$PORT" <<'NODESCRIPT' || printf '警告：renderer 清理未確認（可能已自行還原）。\n' >&2
const [, , port] = process.argv;
const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page = list.find((t) => t.type === "page" && /workbench\.html/.test(t.url) && t.webSocketDebuggerUrl);
if (!page) { console.error("no target"); process.exit(1); }
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
const send = (method, params = {}) => new Promise((res) => {
  const id = Math.floor(Math.random() * 1e9);
  const h = (ev) => { const m = JSON.parse(ev.data); if (m.id === id) { ws.removeEventListener("message", h); res(m); } };
  ws.addEventListener("message", h);
  ws.send(JSON.stringify({ id, method, params }));
});
const expr = `(() => {
  const st = window.__CURSOR_DREAM_SKIN_STATE__;
  if (st && typeof st.cleanup === 'function') { st.cleanup(); return 'cleaned'; }
  return 'nothing';
})()`;
const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true });
console.log(r.result?.result?.value || "unknown");
ws.close();
NODESCRIPT
fi

stop_recorded_injector
/bin/rm -f "$STATE_PATH"

if [ "$KEEP_RUNNING" = "true" ]; then
  printf '皮膚已移除（重載 Cursor 視窗即見原生外觀）。主題檔保留在 %s。\n' "$THEME_DIR"
  exit 0
fi

if cursor_is_running; then
  stop_cursor
fi
/usr/bin/open -a "$CURSOR_BUNDLE" >/dev/null 2>&1 || true
printf '已還原：Cursor 以正常模式重新啟動，皮膚完全移除。\n'
