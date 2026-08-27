#!/bin/bash
# 登入時由 LaunchAgent 呼叫：讀 ~/.cursor-dream-skin/config.json 並套用皮膚。
set -Eeuo pipefail

CONFIG="${HOME}/.cursor-dream-skin/config.json"
[ -f "$CONFIG" ] || exit 0

REPO_ROOT="$(/usr/bin/python3 - "$CONFIG" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["repoRoot"])
PY
)"
THEME="$(/usr/bin/python3 - "$CONFIG" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["theme"])
PY
)"
PORT="$(/usr/bin/python3 - "$CONFIG" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f).get("port", 9351))
PY
)"
RESTART="$(/usr/bin/python3 - "$CONFIG" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print("true" if json.load(f).get("restartExisting", True) else "false")
PY
)"

. "$REPO_ROOT/scripts/common-macos.sh"

# 等登入項目（含 Cursor）先起來
/bin/sleep 8

# 已有 CDP + 注入常駐 → 略過
if [ -f "$STATE_PATH" ]; then
  saved_port="$(state_field 1 2>/dev/null || true)"
  if [ -n "$saved_port" ] && verified_cdp_endpoint "$saved_port"; then
    pid="$(state_field 2 2>/dev/null || true)"
    if [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null; then
      exit 0
    fi
  fi
fi

args=(--port "$PORT" --theme "$REPO_ROOT/$THEME")
[ "$RESTART" = "true" ] && args+=(--restart-existing)

exec "$REPO_ROOT/scripts/start-dream-skin-macos.sh" "${args[@]}"
