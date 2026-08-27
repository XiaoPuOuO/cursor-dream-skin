# Cursor Dream Skin

給 **Cursor Agents** 換一張會呼吸的臉。本機 loopback CDP 注入壁紙與 CSS，**不修改** Cursor 官方安裝包。

> 非 Cursor / Anysphere 官方產品。靈感與主題格式來自 [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin)，但本工具只服務 **Cursor**，且**僅注入「Cursor Agents」獨立視窗**，不套 IDE 主視窗。

## 下載（一般使用者）

1. 到 [Releases](https://github.com/XiaoPuOuO/cursor-dream-skin/releases) 下載 `CursorDreamSkin-v0.1.0.dmg`
2. 打開 DMG，將 **Cursor Dream Skin.app** 拖入「应用程序」
3. 從選單列點 🎨 → **套用皮膚**
4. 若 Cursor 已在執行，App 會以 CDP 重啟 Cursor；請確保 **Cursor Agents** 視窗已開啟

DMG 已 **Developer ID 簽名 + Apple 公證**，一般情況下無需「仍要打開」。

## 選單列 App 功能

| 功能 | 說明 |
|------|------|
| 套用皮膚 | 注入當前主題到 Cursor Agents |
| 驗證 | 檢查注入是否生效 |
| 還原 | 停止 injector 並清除皮膚標記 |
| 已保存的主題 | 切換內建 / 已匯入主題 |
| 導入主題 ZIP… | 匯入 [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 格式主題包 |
| 登入時自動套用 | LaunchAgent 開機帶 CDP 啟動 Cursor |

引擎部署路徑：`~/.cursor/cursor-dream-skin-studio/`  
執行狀態：`~/.cursor-dream-skin/`

## 需求

- macOS 13 Ventura 或更新
- [Cursor](https://cursor.com) 已安裝
- **Node.js 22+**（系統 `node`；injector 需要 WebSocket）
- 選單列 App **或** 終端腳本二選一即可

## 內建主題

| ID | 名稱 |
|----|------|
| `asuna-starlight-glass` | 亞絲娜・星月琉璃 |

對話區透明、sidebar 與輸入框玻璃質感；sidebar 收起後跟 Cursor 原生 chrome（不補假按鈕）。

## 終端用法（進階）

```bash
# 套用內建主題（Cursor 已在跑時加 --restart-existing）
./scripts/start-dream-skin-macos.sh \
  --theme presets/asuna-starlight-glass \
  --restart-existing \
  --save-default

# 匯入 Codex 主題包
node scripts/import-theme.mjs ~/Downloads/my-theme.zip --out presets

# 切換主題
./scripts/switch-theme-macos.sh --theme presets/asuna-starlight-glass --apply

# 還原
./scripts/restore-dream-skin-macos.sh

# 開機自動套用
./scripts/install-autostart-macos.sh --theme presets/asuna-starlight-glass --force
```

預設 CDP 端口 **9351**（避開 Codex / ChatGPT 常用的 9341）。

## 從原始碼建置 App

```bash
# 建 .app
./macos/scripts/build-menubar-app.sh --skip-tests

# 建 DMG
./macos/scripts/build-dmg.sh --skip-tests
```

### 維護者：簽名與公證

```bash
# 1. 本機需有 Developer ID Application 證書
# 2. 建立 notarytool profile（一次性）
xcrun notarytool store-credentials "cursor-dream-skin" --team-id YOUR_TEAM_ID

# 3. 建置 + 公證
./macos/scripts/build-dmg.sh --skip-tests
./macos/scripts/notarize-dmg.sh
```

環境變數 `CODESIGN_IDENTITY` 可覆寫簽名身份；`NOTARY_KEYCHAIN_PROFILE` 可覆寫公證 profile 名稱。

## 原理與安全邊界

1. 以 `--remote-debugging-port` 在本機 `127.0.0.1` 啟動 Cursor（不改 `.app` / `app.asar`）
2. 透過 CDP 只向標題為 **「Cursor Agents」** 的 workbench 頁面注入 CSS 與壁紙
3. watch 常駐进程在 Agents 重載後自動補注入

CDP 在 loopback 上無認證；僅在 Cursor 以調試端口運行時可被本機其他進程連接。還原或正常退出 Cursor 可結束暴露窗口。

## 與 Codex Dream Skin 的關係

| | Codex Dream Skin | Cursor Dream Skin |
|--|------------------|-------------------|
| 目標 App | Codex / ChatGPT Desktop | **Cursor** |
| 注入窗口 | Codex 主界面 | **僅 Cursor Agents** |
| 主題格式 | `theme.json` + `theme.css` + 背景圖 | 可匯入；編譯為 `dream-skin.css` |
| 選單列 App | CodexDreamSkin.dmg | **CursorDreamSkin.dmg** |

**不能**直接安裝 Codex 的 App 來給 Cursor 換膚，兩者互不通用。

## 目錄結構

```
assets/          # 選擇器契約、Codex part 對照、Agents overlay CSS
presets/         # 內建主題
scripts/         # injector、啟動/還原/匯入/開機腳本
macos/
  menubar-app/   # Swift 選單列 App
  scripts/       # build / 簽名 / 公證
docs/            # 設計規格
```

## 授權

MIT — 見 [LICENSE](LICENSE)。主題壁紙等素材依各 preset 授權自行負責；`asuna-starlight-glass` 為使用者提供之 AI 生成範例， redistribution 前請確認肖像與素材權利。

## 致謝

- [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) — CDP 注入架構與主題包格式
- Cursor / VS Code workbench 選擇器契約
