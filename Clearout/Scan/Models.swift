import Darwin

// These go to the page as JSON. The names match Web/app.js.

struct Item: Encodable, Sendable {
    let id: Int
    let name: String
    let path: String
    let size: Int64
    let dir: Bool
    let mtime: Double?
    var locked: String?
    var group: Hint.Group?
    var note: String?
    var reason: String?
    var kids: [Item]?
}

struct FolderView: Encodable, Sendable {
    struct Crumb: Encodable, Sendable {
        let id: Int
        let name: String
    }

    struct Rest: Encodable, Sendable {
        let size: Int64
        let count: Int
    }

    let node: Item
    let crumbs: [Crumb]
    let list: [Item]
    let rest: Rest
    let arcs: [Item]
}

struct ScanProgress: Encodable, Sendable {
    var files = 0
    var bytes: Int64 = 0
    var current: String?
}

struct ScanSummary: Encodable, Sendable {
    let files: Int
    let bytes: Int64
    let blocked: Int
    let online: Int
    let skipped: [String]
}

struct ScannedItem: Sendable {
    let path: String
    let inode: ino_t
    let device: dev_t
    let size: Int64
}
