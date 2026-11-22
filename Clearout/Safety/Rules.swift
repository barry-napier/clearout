import Foundation

struct Hint: Sendable {
    enum Group: String, Codable, Sendable {
        case again, look, app
    }

    let group: Group
    let note: String
}

/// Decides what may go to the Trash. When unsure, the answer is "use Finder".
struct Rules: Sendable {
    let home: String
    private let usesICloud: Bool

    private static let mainFolders: Set<String> = [
        "applications", "applications (parallels)", "desktop", "developer", "documents",
        "downloads", "dropbox", "library", "movies", "music", "parallels", "pictures", "public",
    ]
    // The only parts of ~/Library and hidden home folders that may be trashed.
    private static let cacheParents = [
        "Library/Caches", "Library/Logs", "Library/Developer/Xcode/DerivedData",
        "Library/Developer/Xcode/Archives", "Library/Developer/Xcode/iOS DeviceSupport", ".cache",
    ]
    private static let cacheFolders = [
        "Library/Developer/Xcode/DerivedData", ".npm/_cacache", ".npm/_npx",
        ".bun/install/cache", ".gradle/caches", ".yarn/berry/cache",
    ]
    private static let mediaLibraries: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle", "imovielibrary", "logicx",
    ]
    private static let bundles = mediaLibraries.union(["app", "pvm", "sparsebundle"])

    init(home: String) {
        self.home = home
        var info = stat()
        let link = home + "/Library/Mobile Documents/com~apple~CloudDocs/Documents"
        // When unsure, act as if iCloud is on.
        usesICloud = lstat(link, &info) == 0 || errno != ENOENT
    }

    private static func type(of name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    private func relative(_ path: String) -> String? {
        guard path != home, Paths.inside(path, home) else { return nil }
        return String(path.dropFirst(home.count + 1))
    }

    /// A plain-words reason, or nil when the item can be trashed.
    func lockReason(_ raw: String) -> String? {
        guard let rel = relative(Paths.human(raw)) else { return "Outside your home folder. Use Finder for this." }
        let parts = rel.split(separator: "/").map(String.init)
        guard let first = parts.first, let last = parts.last, !parts.contains(".."), !parts.contains(".") else {
            return "This path is not safe."
        }
        let top = first.lowercased()

        if parts.dropLast().contains(where: { Self.bundles.contains(Self.type(of: $0)) }) {
            return "This is inside an app or library. Removing it can break it."
        }
        if usesICloud, top == "desktop" || top == "documents" {
            return "This is in iCloud. Deleting it deletes it on all your devices."
        }
        if Self.type(of: last) == "pvm" { return "This is a whole virtual computer. Remove it in Parallels." }
        if parts.contains(".git") { return "This is saved code history." }
        if Self.mediaLibraries.contains(Self.type(of: last)) { return "This is a media library. Clean it in its own app." }

        if top == "library" || top.hasPrefix(".") {
            if rel.hasPrefix("Library/Caches/com.apple.") || rel.hasPrefix("Library/Caches/CloudKit") {
                return "macOS looks after this."
            }
            if Self.cacheFolders.contains(where: { Paths.inside(rel, $0) }) { return nil }
            if Self.cacheParents.contains(where: { rel.hasPrefix($0 + "/") }) { return nil }
            return "Apps keep settings and data here. Clean it in that app."
        }
        if parts.count == 1, Self.mainFolders.contains(top) { return "This is a main folder. Open it and pick things inside." }
        if rel.lowercased() == "music/music" { return "This is your music library." }
        return nil
    }

    /// The last check on the real disk, just before a move.
    func checkBeforeTrash(_ item: ScannedItem) throws -> String {
        let path = Paths.human(item.path)
        if let reason = lockReason(path) { throw Failure(reason) }
        let parent = Paths.parent(path)
        guard Paths.real(parent) == parent else { throw Failure("The folder path changed. Scan again.") }
        guard let now = Paths.info(path), now.st_ino == item.inode, now.st_dev == item.device else {
            throw Failure("This changed after the scan. Scan again.")
        }
        guard !CloudGuard.isOnlineOnly(now) else { throw Failure("This is only online. It uses no space here.") }
        return path
    }

    /// Known space hogs for the "Clean up" tab.
    func suggestion(name: String, isFolder: Bool, path raw: String) -> Hint? {
        let path = Paths.human(raw)
        guard let rel = relative(path) else { return nil }

        func again(_ note: String) -> Hint { Hint(group: .again, note: note) }
        func look(_ note: String) -> Hint { Hint(group: .look, note: note) }
        func app(_ note: String) -> Hint { Hint(group: .app, note: note) }

        switch rel {
        case ".Trash":
            return app("Open Trash in Finder, check it, then click Empty.")
        case "Library/Containers/com.docker.docker":
            return app("In Docker, remove images and volumes you do not need. Volumes can hold real data.")
        case "Library/Developer/CoreSimulator/Devices":
            return app("In Xcode, open Devices and Simulators. Delete old test phones.")
        case "Library/Application Support/MobileSync/Backup":
            return app("In Finder, select your iPhone, then Manage Backups.")
        case "Library/Parallels/Downloads":
            return app("Windows installers from Parallels. Once Windows works, delete them in Finder.")
        case ".ollama/models":
            return app("These are AI models. Use \"ollama list\", then \"ollama rm\" with a name.")
        default:
            break
        }

        let type = Self.type(of: name)
        if type == "pvm" { return app("This is a whole virtual computer. Remove it in Parallels if you do not use it.") }

        let parent = Paths.parent(rel)
        if usesICloud, parent == "Desktop" || parent == "Documents" {
            return app("In Finder, right-click it and choose Remove Download. It stays safe in iCloud.")
        }
        guard lockReason(path) == nil else { return nil }
        if Self.cacheFolders.contains(rel) { return again("Saved downloads or build files. Tools make them again.") }

        switch parent {
        case "Library/Caches": return again("App cache. Quit that app first.")
        case "Library/Logs": return again("Old app notes about errors and events.")
        case "Library/Developer/Xcode/iOS DeviceSupport": return again("Xcode gets this again when you plug in that device.")
        case "Library/Developer/Xcode/Archives": return look("Old app builds. Keep any that you shipped.")
        case ".cache": return look("Tool cache. Some tools keep big AI models here.")
        default: break
        }

        if isFolder, !rel.hasPrefix("Library/"), !rel.hasPrefix(".") {
            func beside(_ file: String) -> Bool { Paths.info(Paths.join(Paths.parent(path), file)) != nil }
            if name == "node_modules", beside("package.json") {
                return again("Code add-ons. Your package install command gets them again.")
            }
            if name == ".next" || name == ".turbo", beside("package.json") {
                return again("Build files. Your next build makes them again.")
            }
            if name == "target", beside("Cargo.toml") {
                return again("Rust build files. Your next build makes them again.")
            }
        }
        if !isFolder, rel.hasPrefix("Downloads/"), ["dmg", "pkg", "iso", "ipsw", "xip"].contains(type) {
            return look("An installer. You may not need it now.")
        }
        return nil
    }
}
