import Foundation

public struct ReleaseInfo: Sendable {
    public let version: String
    public let tagName: String
    public let pageURL: URL
    public let dmgDownloadURL: URL?

    public init(version: String, tagName: String, pageURL: URL, dmgDownloadURL: URL?) {
        self.version = version
        self.tagName = tagName
        self.pageURL = pageURL
        self.dmgDownloadURL = dmgDownloadURL
    }
}

public enum UpdateChecker {
    public static let repository = "XiaoPuOuO/cursor-dream-skin"

    public enum CheckError: Error, LocalizedError {
        case invalidResponse
        case releaseNotFound
        case network(String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return L10n.isChinese ? "伺服器回應無效" : "Invalid server response"
            case .releaseNotFound:
                return L10n.isChinese ? "找不到發布版本" : "Release not found"
            case .network(let message):
                return message
            }
        }
    }

    public static func checkForUpdate(currentVersion: String = AppVersion.current) async throws -> ReleaseInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CursorDreamSkin/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CheckError.invalidResponse }

        if http.statusCode == 404 {
            throw CheckError.releaseNotFound
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CheckError.network("HTTP \(http.statusCode)\(body.isEmpty ? "" : ": \(body.prefix(120))")")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tagName = json?["tag_name"] as? String,
              let htmlURLString = json?["html_url"] as? String,
              let pageURL = URL(string: htmlURLString) else {
            throw CheckError.invalidResponse
        }

        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard AppVersion.isRemoteNewer(version, than: currentVersion) else { return nil }

        let assets = json?["assets"] as? [[String: Any]] ?? []
        let dmgURL = assets.compactMap { asset -> URL? in
            guard let name = asset["name"] as? String,
                  name.hasSuffix(".dmg"),
                  let urlString = asset["browser_download_url"] as? String else { return nil }
            return URL(string: urlString)
        }.first

        return ReleaseInfo(version: version, tagName: tagName, pageURL: pageURL, dmgDownloadURL: dmgURL)
    }

    public static func downloadDMG(_ release: ReleaseInfo) async throws -> URL {
        guard let remoteURL = release.dmgDownloadURL else {
            throw CheckError.network(L10n.isChinese ? "此版本沒有 DMG 附件" : "This release has no DMG asset")
        }

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CheckError.network(L10n.isChinese ? "下載失敗" : "Download failed")
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        let fileName = remoteURL.lastPathComponent.isEmpty ? "CursorDreamSkin-\(release.version).dmg" : remoteURL.lastPathComponent
        let destination = downloads.appendingPathComponent(fileName)

        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: tempURL, to: destination)
        return destination
    }
}
