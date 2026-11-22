import Foundation

enum Paths {
    static let data = "/System/Volumes/Data"

    /// The true path, with shortcuts followed. Foundation's version drops "/private".
    static func real(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A whole-disk scan sees /System/Volumes/Data/Users/... for /Users/...
    static func human(_ path: String) -> String {
        if path == data { return "/" }
        return path.hasPrefix(data + "/") ? String(path.dropFirst(data.count)) : path
    }

    static func inside(_ path: String, _ parent: String) -> Bool {
        path == parent || path.hasPrefix(parent + "/")
    }

    static func join(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    static func name(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func info(_ path: String) -> stat? {
        var info = stat()
        return lstat(path, &info) == 0 ? info : nil
    }
}
