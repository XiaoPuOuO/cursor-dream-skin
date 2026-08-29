import Foundation

public enum L10n {
    public static var isChinese: Bool {
        Locale.preferredLanguages.contains { $0.lowercased().contains("zh") }
    }

    public static var appTitle: String { "Cursor Dream Skin" }

    public static var notApplied: String { t("（未套用）", "(Not applied)") }
    public static var applySkin: String { t("套用皮膚", "Apply Skin") }
    public static var verify: String { t("驗證", "Verify") }
    public static var restore: String { t("還原", "Restore") }
    public static var savedThemes: String { t("已保存的主題", "Saved Themes") }
    public static var noThemes: String { t("（無主題）", "(No themes)") }
    public static var importTheme: String { t("導入主題 ZIP…", "Import Theme ZIP…") }
    public static var autostartSkin: String { t("登入時自動套用皮膚", "Apply Skin at Login") }
    public static var autostartApp: String { t("登入時打開 Cursor Dream Skin", "Open Cursor Dream Skin at Login") }
    public static var openThemesFolder: String { t("打開主題資料夾", "Open Themes Folder") }
    public static var checkUpdates: String { t("檢查更新…", "Check for Updates…") }
    public static var quit: String { t("退出", "Quit") }
    public static var later: String { t("稍後", "Later") }
    public static var download: String { t("下載", "Download") }
    public static var ok: String { t("好", "OK") }
    public static var downloadingUpdate: String { t("正在下載更新…", "Downloading update…") }

    public static func statusLine(_ theme: String) -> String { "● \(theme)" }

    public static func downloadUpdate(_ version: String) -> String {
        t("下載更新 \(version)", "Download Update \(version)")
    }

    public static func versionLine(_ version: String) -> String {
        t("版本 \(version)", "Version \(version)")
    }

    public static func upToDate(_ version: String) -> String {
        t("目前已是最新版本（\(version)）。", "You're up to date (\(version)).")
    }

    public static func updateAvailable(_ version: String) -> String {
        t("新版本 \(version) 可用。是否下載？", "New version \(version) is available. Download now?")
    }

    public static func updateCheckFailed(_ reason: String) -> String {
        t("無法檢查更新：\(reason)", "Couldn't check for updates: \(reason)")
    }

    public static func downloadComplete(_ path: String) -> String {
        t(
            "已下載至：\n\(path)\n\n請打開 DMG，將 Cursor Dream Skin 拖入「应用程序」以完成更新。",
            "Downloaded to:\n\(path)\n\nOpen the DMG and drag Cursor Dream Skin to Applications to update."
        )
    }

    public static func downloadFailed(_ reason: String) -> String {
        t("下載失敗：\(reason)", "Download failed: \(reason)")
    }

    public static var selectThemeZip: String {
        t("選擇 Codex 主題 ZIP 或已解壓目錄", "Select a Codex theme ZIP or extracted folder")
    }

    public static var selectThemeFirst: String {
        t("請先選擇主題，或匯入主題包。", "Select a theme or import a theme pack first.")
    }

    public static var themeImported: String { t("主題已匯入。", "Theme imported.") }

    public static var importFailed: String {
        t("匯入失敗，請確認 ZIP 格式。", "Import failed. Check the ZIP format.")
    }

    public static var applyOnceFirst: String {
        t("請先套用一次皮膚以儲存預設主題。", "Apply a skin once to save the default theme.")
    }

    public static var loginItemAdded: String {
        t(
            "已在「系統設定 → 一般 → 登入項目」加入 Cursor Dream Skin。若被關閉，請在該處手動允許。",
            "Cursor Dream Skin was added under System Settings → General → Login Items. Enable it there if disabled."
        )
    }

    public static func loginItemFailed(_ error: String) -> String {
        t(
            "無法設定登入項目：\(error)\n\n請確認 Cursor Dream Skin.app 已安裝在「应用程序」資料夾，且為已簽名版本。",
            "Couldn't configure login item: \(error)\n\nEnsure Cursor Dream Skin.app is in Applications and properly signed."
        )
    }

    public static func scriptMissing(_ name: String) -> String {
        t("找不到腳本：\(name)", "Script not found: \(name)")
    }

    public static func scriptFailed(_ code: Int32, _ output: String) -> String {
        t("腳本失敗 (\(code))：\(output)", "Script failed (\(code)): \(output)")
    }

    public static func scriptFailedGeneric(_ name: String) -> String {
        t("腳本 \(name) 失敗", "Script \(name) failed")
    }

    public static func nodeScriptFailed(_ name: String) -> String {
        t("Node 腳本 \(name) 失敗", "Node script \(name) failed")
    }

    private static func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}
