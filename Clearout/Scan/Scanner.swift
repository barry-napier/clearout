import Foundation
import os

/// Reads names and sizes on its own thread. It never opens or changes a file.
final class Scanner: @unchecked Sendable {
    private struct Shared {
        var progress = ScanProgress()
        var cancelled = false
    }

    private let root: String
    private let cloudStorage: String // reading this can hang on the network
    private let shared = OSAllocatedUnfairLock(initialState: Shared())

    // Only the scan thread touches these.
    private var nodes: [Int: Node] = [:]
    private var linked: Set<ino_t> = []
    private var skipped: [String] = []
    private var nextID = 0
    private var files = 0
    private var bytes: Int64 = 0
    private var blocked = 0
    private var online = 0
    private var visits = 0
    private var cancelled = false

    private static let smallFile: Int64 = 1_000_000
    private static let loginFiles = ["Cookies", "Login Data", "cookies.sqlite", "logins.json", "key4.db"]
    private static let nameOffset = MemoryLayout<dirent>.offset(of: \dirent.d_name)!

    init(root: String, home: String) {
        self.root = root
        cloudStorage = home + "/Library/CloudStorage"
    }

    var progress: ScanProgress {
        shared.withLock { $0.progress }
    }

    func cancel() {
        shared.withLock { $0.cancelled = true }
    }

    func run() async throws -> ScanOutput {
        guard CloudGuard.isOn else { throw Failure("Cannot block iCloud downloads, so the scan did not start.") }
        return try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result { try self.scan() }) }
            thread.stackSize = 16 << 20 // folders can nest very deeply
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private func scan() throws -> ScanOutput {
        guard let info = Paths.info(root) else { throw Failure("Clearout cannot read that folder.") }
        bytes = info.st_blocks * 512
        let top = Node(id: 1, name: root, parent: nil, info: info, size: bytes)
        nextID = 1
        nodes[1] = top
        walk(top, root)
        if cancelled { throw CancellationError() }
        linked = []
        let summary = ScanSummary(files: files, bytes: top.size, blocked: blocked, online: online, skipped: skipped)
        return ScanOutput(root: root, top: top, nodes: nodes, summary: summary)
    }

    private func report(_ path: String) {
        let progress = ScanProgress(files: files, bytes: bytes, current: Paths.human(path))
        cancelled = shared.withLock {
            $0.progress = progress
            return $0.cancelled
        }
    }

    private func walk(_ node: Node, _ path: String) {
        visits += 1
        if visits % 64 == 1 { report(path) }
        if cancelled { return }

        if node.hasOnlineOnly {
            online += 1 // only online, so it takes no space here
            return
        }
        if path.hasSuffix("/CloudStorage"), Paths.human(path) == cloudStorage {
            skipped.append(cloudStorage)
            return
        }
        guard let folder = opendir(path) else {
            let code = errno
            if code == EDEADLK {
                online += 1
                node.hasOnlineOnly = true
            } else if code == EPERM || code == EACCES {
                blocked += 1
                if skipped.count < 100 { skipped.append(Paths.human(path)) }
            }
            return
        }

        let descriptor = dirfd(folder)
        var folders: [Node] = []
        while let entry = readdir(folder) {
            let raw = (UnsafeRawPointer(entry) + Self.nameOffset).assumingMemoryBound(to: CChar.self)
            if raw[0] == 46, raw[1] == 0 || (raw[1] == 46 && raw[2] == 0) { continue } // "." and ".."

            var info = stat()
            guard fstatat(descriptor, raw, &info, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            guard info.st_dev == node.device else { continue } // another disk

            let isFolder = info.st_mode & S_IFMT == S_IFDIR
            var size = info.st_blocks * 512
            if !isFolder, info.st_nlink > 1, !linked.insert(info.st_ino).inserted { size = 0 }
            bytes += size
            if strcmp(raw, ".git") == 0 { node.isRepo = true }

            let isLogin = !isFolder && info.st_size > 0 && Self.loginFiles.contains { strcmp(raw, $0) == 0 }
            if isLogin { node.hasLogins = true }

            if !isFolder {
                files += 1
                if files % 4096 == 0 {
                    report(path)
                    if cancelled { break }
                }
                node.size += size
                // Finder rewrites .DS_Store when you only look, so it is not a change.
                if strcmp(raw, ".DS_Store") != 0 { node.newest = max(node.newest, Double(info.st_mtimespec.tv_sec) * 1000) }
                if CloudGuard.isOnlineOnly(info) { node.hasOnlineOnly = true }
                // Small files are grouped, so millions of them fit in memory.
                if size < Self.smallFile {
                    node.smallSize += size
                    node.smallCount += 1
                    continue
                }
            }

            nextID += 1
            let child = Node(id: nextID, name: String(cString: raw), parent: node, info: info, size: size)
            child.hasLogins = isLogin
            nodes[child.id] = child
            node.kids.append(child)
            if isFolder { folders.append(child) }
        }
        closedir(folder)

        for child in folders {
            if cancelled { return }
            autoreleasepool { walk(child, Paths.join(path, child.name)) }
            node.size += child.size
            node.newest = max(node.newest, child.newest)
            if child.hasOnlineOnly { node.hasOnlineOnly = true }
            if child.hasLogins { node.hasLogins = true }
        }
        node.kids.sort { $0.size > $1.size }
    }
}
