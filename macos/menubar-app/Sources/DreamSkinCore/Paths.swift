import Foundation

public enum DreamSkinPaths {
    public static let engineRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".cursor/cursor-dream-skin-studio", isDirectory: true)
    public static let stateRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".cursor-dream-skin", isDirectory: true)
    public static let userThemesRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/CursorDreamSkin/themes", isDirectory: true)
    public static let launchAgentPlist = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/LaunchAgents/com.cursor-dream-skin.autostart.plist")

    public static func bundledEngineRoot() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/engine", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static func script(_ name: String) -> URL {
        engineRoot.appendingPathComponent("scripts/\(name)")
    }
}

public struct ThemeInfo: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let directory: URL

    public var relativePath: String {
        directory.path.replacingOccurrences(of: DreamSkinPaths.engineRoot.path + "/", with: "")
    }
}

public enum ThemeStore {
    public static func listThemes() -> [ThemeInfo] {
        var themes: [ThemeInfo] = []
        let roots = [
            DreamSkinPaths.engineRoot.appendingPathComponent("presets", isDirectory: true),
            DreamSkinPaths.userThemesRoot
        ]
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for dir in entries where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let themeJSON = dir.appendingPathComponent("theme.json")
                guard let data = try? Data(contentsOf: themeJSON),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String else { continue }
                let name = (json["name"] as? String) ?? id
                themes.append(ThemeInfo(id: id, name: name, directory: dir))
            }
        }
        var seen = Set<String>()
        return themes.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func activeThemeName() -> String? {
        let config = DreamSkinPaths.stateRoot.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let themeRel = json["theme"] as? String else { return nil }
        let themeDir = DreamSkinPaths.engineRoot.appendingPathComponent(themeRel)
        let themeJSON = themeDir.appendingPathComponent("theme.json")
        guard let data = try? Data(contentsOf: themeJSON),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["name"] as? String) ?? (json["id"] as? String)
    }

    public static func autostartEnabled() -> Bool {
        FileManager.default.fileExists(atPath: DreamSkinPaths.launchAgentPlist.path)
    }
}

public enum EngineInstaller {
    public static func installedVersion() -> String? {
        let file = DreamSkinPaths.engineRoot.appendingPathComponent("VERSION")
        return try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func bundledVersion() -> String? {
        guard let bundled = DreamSkinPaths.bundledEngineRoot() else { return nil }
        let file = bundled.appendingPathComponent("VERSION")
        return try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func needsInstall() -> Bool {
        guard DreamSkinPaths.bundledEngineRoot() != nil else { return false }
        let required = ["scripts/start-dream-skin-macos.sh", "scripts/injector.mjs", "assets/dream-skin.css"]
        for rel in required {
            let path = DreamSkinPaths.engineRoot.appendingPathComponent(rel).path
            if !FileManager.default.fileExists(atPath: path) { return true }
        }
        guard let bv = bundledVersion(), let iv = installedVersion() else { return true }
        return bv != iv
    }
}
