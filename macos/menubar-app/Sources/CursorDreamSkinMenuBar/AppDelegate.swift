import AppKit
import DreamSkinCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var autostartItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEngineIfNeeded()
        try? FileManager.default.createDirectory(at: DreamSkinPaths.userThemesRoot, withIntermediateDirectories: true)
        setupStatusItem()
    }

    private func installEngineIfNeeded() {
        guard let bundled = DreamSkinPaths.bundledEngineRoot() else { return }
        guard EngineInstaller.needsInstall() else { return }
        deployEngine(from: bundled)
    }

    private func deployEngine(from bundled: URL) {
        let dest = DreamSkinPaths.engineRoot
        let fm = FileManager.default
        let staging = dest.deletingLastPathComponent().appendingPathComponent(".cursor-dream-skin-studio.staging")
        let previous = dest.deletingLastPathComponent().appendingPathComponent(".cursor-dream-skin-studio.previous")
        try? fm.removeItem(at: staging)
        try? fm.copyItem(at: bundled, to: staging)
        try? fm.removeItem(at: previous)
        if fm.fileExists(atPath: dest.path) {
            try? fm.moveItem(at: dest, to: previous)
        }
        try? fm.moveItem(at: staging, to: dest)
        try? fm.removeItem(at: previous)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎨"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let active = ThemeStore.activeThemeName() ?? "（未套用）"
        let status = NSMenuItem(title: "● \(active)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(makeItem("套用皮膚", action: #selector(applySkin)))
        menu.addItem(makeItem("驗證", action: #selector(verifySkin)))
        menu.addItem(makeItem("還原", action: #selector(restoreSkin)))
        menu.addItem(.separator())

        let themesMenu = NSMenuItem(title: "已保存的主題", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let themes = ThemeStore.listThemes()
        if themes.isEmpty {
            let empty = NSMenuItem(title: "（無主題）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            for theme in themes {
                let item = NSMenuItem(title: theme.name, action: #selector(switchTheme(_:)), keyEquivalent: "")
                item.representedObject = theme
                item.target = self
                sub.addItem(item)
            }
        }
        themesMenu.submenu = sub
        menu.addItem(themesMenu)

        menu.addItem(makeItem("導入主題 ZIP…", action: #selector(importTheme)))
        menu.addItem(.separator())

        autostartItem = NSMenuItem(title: "登入時自動套用", action: #selector(toggleAutostart), keyEquivalent: "")
        autostartItem.target = self
        autostartItem.state = ThemeStore.autostartEnabled() ? .on : .off
        menu.addItem(autostartItem)

        menu.addItem(makeItem("打開主題資料夾", action: #selector(openThemesFolder)))
        menu.addItem(.separator())
        menu.addItem(makeItem("退出", action: #selector(quitApp)))

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func applySkin() {
        guard let theme = currentThemePath() else {
            showInfo("請先選擇主題，或匯入主題包。")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ScriptRunner.run("start-dream-skin-macos.sh", arguments: [
                    "--theme", theme,
                    "--restart-existing",
                    "--save-default"
                ])
                DispatchQueue.main.async { self.rebuildMenu() }
            } catch {}
        }
    }

    @objc private func verifySkin() {
        let themeDir = DreamSkinPaths.stateRoot.appendingPathComponent("theme").path
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let out = try ScriptRunner.runNode("injector.mjs", arguments: [
                    "--verify", "--port", "9351", "--theme-dir", themeDir
                ])
                DispatchQueue.main.async { self.showInfo(out) }
            } catch {}
        }
    }

    @objc private func restoreSkin() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ScriptRunner.run("restore-dream-skin-macos.sh")
                DispatchQueue.main.async { self.rebuildMenu() }
            } catch {}
        }
    }

    @objc private func switchTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? ThemeInfo else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ScriptRunner.run("switch-theme-macos.sh", arguments: [
                    "--theme", theme.directory.path,
                    "--apply"
                ])
                DispatchQueue.main.async { self.rebuildMenu() }
            } catch {}
        }
    }

    @objc private func importTheme() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "選擇 Codex 主題 ZIP 或已解壓目錄"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let presets = DreamSkinPaths.engineRoot.appendingPathComponent("presets")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ScriptRunner.runNode("import-theme.mjs", arguments: [url.path, "--out", presets.path])
                DispatchQueue.main.async {
                    self.rebuildMenu()
                    self.showInfo("主題已匯入。")
                }
            } catch {
                DispatchQueue.main.async { self.showInfo("匯入失敗，請確認 ZIP 格式。") }
            }
        }
    }

    @objc private func toggleAutostart() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if ThemeStore.autostartEnabled() {
                    _ = try ScriptRunner.run("uninstall-autostart-macos.sh")
                } else {
                    guard let theme = self.currentThemeRelative() else {
                        DispatchQueue.main.async { self.showInfo("請先套用一次皮膚以儲存預設主題。") }
                        return
                    }
                    _ = try ScriptRunner.run("install-autostart-macos.sh", arguments: [
                        "--theme", theme,
                        "--force"
                    ])
                }
                DispatchQueue.main.async { self.rebuildMenu() }
            } catch {}
        }
    }

    @objc private func openThemesFolder() {
        try? FileManager.default.createDirectory(at: DreamSkinPaths.userThemesRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(DreamSkinPaths.userThemesRoot)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func currentThemePath() -> String? {
        if let rel = currentThemeRelative() {
            let path = DreamSkinPaths.engineRoot.appendingPathComponent(rel).path
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return ThemeStore.listThemes().first?.directory.path
    }

    private func currentThemeRelative() -> String? {
        let config = DreamSkinPaths.stateRoot.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let theme = json["theme"] as? String else { return nil }
        return theme
    }

    private func showInfo(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Cursor Dream Skin"
        alert.informativeText = text
        alert.runModal()
    }
}
