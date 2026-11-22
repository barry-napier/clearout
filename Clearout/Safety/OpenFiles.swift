import Foundation

/// Knows which apps have files open, so nothing is moved from under a running app.
actor OpenFiles {
    struct Use: Sendable {
        let app: String
        let path: String
    }

    private var uses: [Use] = []
    private var readAt = Date.distantPast
    /// One answer serves a whole pile of picks, but not for long.
    private static let freshFor: TimeInterval = 5

    /// A plain-words reason, or nil. When it cannot tell, the answer is "in use".
    func reason(path: String) async -> String? {
        if Date().timeIntervalSince(readAt) > Self.freshFor {
            guard let fresh = await Task.detached(operation: { Self.read() }).value else {
                return "Clearout cannot check if an app is using this."
            }
            uses = fresh
            readAt = Date()
        }
        guard let use = uses.first(where: { Paths.inside($0.path, path) }) else { return nil }
        return "\(use.app) is using this. Quit it first."
    }

    /// lsof prints "p" lines for processes, "c" for their names and "n" for paths.
    static func parse(_ output: String, ignoring ownID: Int32) -> [Use] {
        var found: [Use] = []
        var app = ""
        var skip = false
        for line in output.split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": skip = Int32(value) == ownID
            case "c": app = value.replacingOccurrences(of: "\\x20", with: " ")
            case "n" where !skip && value.hasPrefix("/"): found.append(Use(app: app, path: Paths.human(value)))
            default: break
            }
        }
        return found
    }

    private static func read() -> [Use]? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +c 0: whole app names. -w: no warnings.
        task.arguments = ["-w", "-n", "-P", "+c", "0", "-F", "pcn"]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8" // without it, names like café come back garbled
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }

        let stop = DispatchWorkItem { task.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: stop)
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        stop.cancel()
        // lsof exits with 1 for small problems, so judge by the output. A cut-off list is no answer.
        guard task.terminationReason == .exit, !output.isEmpty else { return nil }
        return parse(String(decoding: output, as: UTF8.self), ignoring: ProcessInfo.processInfo.processIdentifier)
    }
}
