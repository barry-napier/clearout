import Darwin

/// One folder, or one file of 1 MB or more.
/// Only the scan thread changes it, and after that only DiskMap does.
final class Node {
    let id: Int
    let name: String
    unowned let parent: Node?
    let isFolder: Bool
    let inode: ino_t
    let device: dev_t
    let modified: Double
    var size: Int64
    /// The newest change to any file inside, in milliseconds. 0 until a file is seen.
    var newest: Double = 0
    /// It is, or holds, something that is only online.
    var hasOnlineOnly: Bool
    /// It is, or holds, a browser's saved cookies or passwords.
    var hasLogins = false
    /// It is the top of a code project (it has a .git folder or file).
    var isRepo = false
    var kids: [Node] = []
    var smallSize: Int64 = 0
    var smallCount = 0

    init(id: Int, name: String, parent: Node?, info: stat, size: Int64) {
        self.id = id
        self.name = name
        self.parent = parent
        self.size = size
        isFolder = info.st_mode & S_IFMT == S_IFDIR
        inode = info.st_ino
        device = info.st_dev
        modified = Double(info.st_mtimespec.tv_sec) * 1000
        hasOnlineOnly = CloudGuard.isOnlineOnly(info)
    }
}

/// A finished scan, handed over from the scan thread to a DiskMap.
struct ScanOutput: @unchecked Sendable {
    let root: String
    let top: Node
    let nodes: [Int: Node]
    let summary: ScanSummary
}
