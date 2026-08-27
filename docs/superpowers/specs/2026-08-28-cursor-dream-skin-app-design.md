# Cursor Dream Skin 菜单栏 App — 设计规格

**日期：** 2026-08-28  
**版本：** v1 标准版  
**状态：** 已批准，实施中

## 目标

为 Cursor Agents 提供类似 Codex Dream Skin 的原生 macOS 菜单栏 App，使用户无需每次手动运行 shell 脚本即可套用、切换、导入主题。

## 非目标（v1）

- 不换图 / 在线 Studio
- 多语言本地化
- 自动更新检查
- Windows 版
- IDE 主窗口注入（仅 Cursor Agents）

## 架构

```
Cursor Dream Skin.app（LSUIElement 菜单栏）
  └─ Contents/Resources/engine/     # build 时打包
        ↓ 首次启动 deploy（VERSION 比对）
~/.cursor/cursor-dream-skin-studio/   # 引擎：scripts、assets、presets
~/.cursor-dream-skin/                 # 状态：theme staging、config、日志
~/Library/Application Support/CursorDreamSkin/themes/  # 用户导入主题
```

App 为 **AppKit NSMenu 壳**，所有操作通过 `/bin/bash` 调用已部署引擎脚本。不修改 Cursor 本体。

## 菜单结构（v1 标准版）

| 菜单项 | 行为 |
|--------|------|
| ● 当前主题名 | 只读状态 |
| 套用皮肤 | `start-dream-skin-macos.sh --restart-existing --save-default` |
| 验证 | `injector.mjs --verify` |
| 还原 | `restore-dream-skin-macos.sh` |
| 已保存的主题 ▶ | 列出 presets + 用户 themes，点击切换并套用 |
| 导入主题 ZIP… | NSOpenPanel → `import-theme.mjs` |
| ☑ 登录时自动套用 | toggle `install/uninstall-autostart-macos.sh` |
| 打开主题文件夹 | Finder 打开 Application Support/themes |
| 退出 | 终止 App（injector watch 常駐不受影响） |

## 引擎部署

- `install-dream-skin-macos.sh` 使用 rsync 原子部署到 `~/.cursor/cursor-dream-skin-studio`
- App 启动时比对 bundle `engine/VERSION` 与已安装 VERSION，不一致则重新 deploy
- autostart `config.json` 的 `repoRoot` 指向 studio 路径

## Build 产物

- `macos/scripts/build-menubar-app.sh` → `macos/release/Cursor Dream Skin.app`
- `macos/scripts/build-dmg.sh` → `macos/release/CursorDreamSkin-v0.1.0.dmg`
- ad-hoc codesign（与 Codex 相同，未签名 DMG）

## 依赖

- macOS 13+
- 系统 Node.js 22+（injector WebSocket）
- 已安装 Cursor.app

## Agents CSS 补充（同批交付）

针对 CDP 实测未透明区域：

- `.composer-human-message.standalone-glass` → 轻量玻璃
- `.ui-code-block` → 玻璃代码块
- `.ui-markdown__table` / `bg-muted` → 半透明表格
- 对话容器链全透明

## 验收标准

1. 双击 DMG 安装后，菜单栏出现 🎨，一点「套用皮肤」Agents 窗口生效
2. 主题列表可切换 asuna-starlight-glass 与用户导入主题
3. 导入 Codex ZIP 成功并出现在列表
4. 登录自动套用 toggle 可安装/卸载 LaunchAgent
5. CSS：用户消息泡与代码块不再为实色 rgb(24,24,24)
