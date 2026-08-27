import AppKit
import DreamSkinCore

final class ScriptRunner {
    enum RunError: Error, LocalizedError {
        case scriptMissing(String)
        case failed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing(let name): return "找不到脚本：\(name)"
            case .failed(let code, let output): return "脚本失败 (\(code))：\(output)"
            }
        }
    }

    @discardableResult
    static func run(_ scriptName: String, arguments: [String] = [], showErrors: Bool = true) throws -> String {
        let url = DreamSkinPaths.script(scriptName)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw RunError.scriptMissing(scriptName)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [url.path] + arguments
        task.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if task.terminationStatus != 0 {
            if showErrors {
                let alert = NSAlert()
                alert.messageText = "Cursor Dream Skin"
                alert.informativeText = output.isEmpty ? "脚本 \(scriptName) 失败" : output
                alert.alertStyle = .warning
                alert.runModal()
            }
            throw RunError.failed(task.terminationStatus, output)
        }
        return output
    }

    static func runNode(_ scriptName: String, arguments: [String] = [], showErrors: Bool = true) throws -> String {
        let node = ProcessInfo.processInfo.environment["NODE_OVERRIDE"]
            ?? which("node")
            ?? "/usr/local/bin/node"
        let script = DreamSkinPaths.script(scriptName)
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw RunError.scriptMissing(scriptName)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: node)
        task.arguments = [script.path] + arguments
        task.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if task.terminationStatus != 0 {
            if showErrors {
                let alert = NSAlert()
                alert.messageText = "Cursor Dream Skin"
                alert.informativeText = output.isEmpty ? "Node 脚本 \(scriptName) 失败" : output
                alert.alertStyle = .warning
                alert.runModal()
            }
            throw RunError.failed(task.terminationStatus, output)
        }
        return output
    }

    private static func which(_ name: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
