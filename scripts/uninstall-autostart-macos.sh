#!/bin/bash
# 移除登入時自動套用（LaunchAgent）。
set -Eeuo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

if [ -f "$LAUNCH_AGENT_PLIST" ]; then
  /bin/launchctl bootout "gui/$(/usr/bin/id -u)" "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
  /bin/rm -f "$LAUNCH_AGENT_PLIST"
  printf '已移除 LaunchAgent：%s\n' "$LAUNCH_AGENT_LABEL"
else
  printf 'LaunchAgent 不存在，無需移除。\n'
fi
