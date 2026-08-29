import AppKit
import DreamSkinCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var skinAutostartItem: NSMenuItem!
    private var appLoginItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var pendingUpdate: ReleaseInfo?
    private var updateCheckInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEngineIfNeeded()
        try? FileManager.default.createDirectory(at: DreamSkinPaths.userThemesRoot, withIntermediateDirectories: true)
        setupStatusItem()
        checkForUpdatesInBackground()
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

        let active = ThemeStore.activeThemeName() ?? L10n.notApplied
        let status = NSMenuItem(title: L10n.statusLine(active), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(makeItem(L10n.applySkin, action: #selector(applySkin)))
        menu.addItem(makeItem(L10n.verify, action: #selector(verifySkin)))
        menu.addItem(makeItem(L10n.restore, action: #selector(restoreSkin)))
        menu.addItem(.separator())

        let themesMenu = NSMenuItem(title: L10n.savedThemes, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let themes = ThemeStore.listThemes()
        if themes.isEmpty {
            let empty = NSMenuItem(title: L10n.noThemes, action: nil, keyEquivalent: "")
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

        menu.addItem(makeItem(L10n.importTheme, action: #selector(importTheme)))
        menu.addItem(.separator())

        skinAutostartItem = NSMenuItem(
            title: L10n.autostartSkin,
            action: #selector(toggleSkinAutostart),
            keyEquivalent: ""
        )
        skinAutostartItem.target = self
        skinAutostartItem.state = ThemeStore.autostartEnabled() ? .on : .off
        menu.addItem(skinAutostartItem)

        appLoginItem = NSMenuItem(
            title: L10n.autostartApp,
            action: #selector(toggleAppLogin),
            keyEquivalent: ""
        )
        appLoginItem.target = self
        appLoginItem.state = AppLoginItem.isEnabled() ? .on : .off
        menu.addItem(appLoginItem)

        menu.addItem(makeItem(L10n.openThemesFolder, action: #selector(openThemesFolder)))
        menu.addItem(.separator())

        let versionItem = NSMenuItem(title: L10n.versionLine(AppVersion.current), action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        if let release = pendingUpdate {
            updateItem = makeItem(L10n.downloadUpdate(release.version), action: #selector(downloadPendingUpdate))
        } else {
            updateItem = makeItem(
                updateCheckInProgress ? "\(L10n.checkUpdates) …" : L10n.checkUpdates,
                action: #selector(checkForUpdates)
            )
        }
        updateItem.isEnabled = !updateCheckInProgress
        menu.addItem(updateItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.quit, action: #selector(quitApp)))

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func checkForUpdatesInBackground() {
        updateCheckInProgress = true
        Task {
            defer {
                Task { @MainActor in
                    self.updateCheckInProgress = false
                    self.rebuildMenu()
                }
            }
            do {
                if let release = try await UpdateChecker.checkForUpdate() {
                    await MainActor.run {
                        self.pendingUpdate = release
                        self.rebuildMenu()
                    }
                }
            } catch {
                // Silent on background failure; user can check manually.
            }
        }
    }

    @objc private func checkForUpdates() {
        guard !updateCheckInProgress else { return }
        updateCheckInProgress = true
        rebuildMenu()

        Task {
            defer {
                Task { @MainActor in
                    self.updateCheckInProgress = false
                    self.rebuildMenu()
                }
            }
            do {
                if let release = try await UpdateChecker.checkForUpdate() {
                    await MainActor.run {
                        self.pendingUpdate = release
                        self.rebuildMenu()
                        self.promptDownloadUpdate(release)
                    }
                } else {
                    await MainActor.run {
                        self.pendingUpdate = nil
                        self.showInfo(L10n.upToDate(AppVersion.current))
                    }
                }
            } catch {
                await MainActor.run {
                    self.showInfo(L10n.updateCheckFailed(error.localizedDescription))
                }
            }
        }
    }

    @objc private func downloadPendingUpdate() {
        guard let release = pendingUpdate else {
            checkForUpdates()
            return
        }
        promptDownloadUpdate(release)
    }

    private func promptDownloadUpdate(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = L10n.appTitle
        alert.informativeText = L10n.updateAvailable(release.version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.download)
        alert.addButton(withTitle: L10n.later)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        downloadUpdate(release)
    }

    private func downloadUpdate(_ release: ReleaseInfo) {
        updateCheckInProgress = true
        rebuildMenu()

        Task {
            defer {
                Task { @MainActor in
                    self.updateCheckInProgress = false
                    self.rebuildMenu()
                }
            }
            do {
                let localURL = try await UpdateChecker.downloadDMG(release)
                await MainActor.run {
                    NSWorkspace.shared.open(localURL)
                    self.showInfo(L10n.downloadComplete(localURL.path))
                }
            } catch {
                await MainActor.run {
                    if release.dmgDownloadURL == nil {
                        NSWorkspace.shared.open(release.pageURL)
                    }
                    self.showInfo(L10n.downloadFailed(error.localizedDescription))
                }
            }
        }
    }

    @objc private func applySkin() {
        guard let theme = currentThemePath() else {
            showInfo(L10n.selectThemeFirst)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ScriptRunner.run("start-dream-skin-macos.sh", arguments: [
                    "--theme", theme,
                    "--restart-existing",
                    "--save-default"
                ], showErrors: false)
                DispatchQueue.main.async { self.rebuildMenu() }
            } catch {
                DispatchQueue.main.async {
                    self.showInfo(error.localizedDescription)
                }
            }
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
        panel.message = L10n.selectThemeZip
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let presets = DreamSkinPaths.engineRoot.appendingPathComponent("presets")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ScriptRunner.runNode("import-theme.mjs", arguments: [url.path, "--out", presets.path])
                DispatchQueue.main.async {
                    self.rebuildMenu()
                    self.showInfo(L10n.themeImported)
                }
            } catch {
                DispatchQueue.main.async { self.showInfo(L10n.importFailed) }
            }
        }
    }

    @objc private func toggleSkinAutostart() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if ThemeStore.autostartEnabled() {
                    _ = try ScriptRunner.run("uninstall-autostart-macos.sh")
                } else {
                    guard let theme = self.currentThemeRelative() else {
                        DispatchQueue.main.async {
                            self.showInfo(L10n.applyOnceFirst)
                        }
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

    @objc private func toggleAppLogin() {
        let enable = !AppLoginItem.isEnabled()
        do {
            try AppLoginItem.setEnabled(enable)
            rebuildMenu()
            if enable && AppLoginItem.statusDescription == "requiresApproval" {
                showInfo(L10n.loginItemAdded)
            }
        } catch {
            showInfo(L10n.loginItemFailed(error.localizedDescription))
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
        let work = {
            let alert = NSAlert()
            alert.messageText = L10n.appTitle
            alert.informativeText = text
            alert.addButton(withTitle: L10n.ok)
            alert.runModal()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
