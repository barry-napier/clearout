import Foundation

/// Answers questions about a finished scan.
actor DiskMap {
    private let root: String
    private let top: Node
    private var nodes: [Int: Node]
    private let rules: Rules

    private static let listLimit = 500
    private static let cleanupMinimum: Int64 = 20_000_000
    private static let biggestMinimum: Int64 = 50_000_000

    init(_ output: ScanOutput, rules: Rules) {
        root = output.root
        top = output.top
        nodes = output.nodes
        self.rules = rules
    }

    private func find(_ id: Int) throws -> Node {
        guard let node = nodes[id] else { throw Failure("That item is gone. Scan again.") }
        return node
    }

    private func path(of node: Node) -> String {
        guard let parent = node.parent else { return root }
        return Paths.join(path(of: parent), node.name)
    }

    private func title(of node: Node) -> String {
        if node.parent != nil { return node.name }
        let shown = Paths.human(root)
        return shown == "/" ? "Whole Mac" : Paths.name(shown)
    }

    private func describe(_ node: Node) -> Item {
        let full = path(of: node)
        let online = node.hasOnlineOnly ? "Some of this is only online. Use Finder for this." : nil
        return Item(
            id: node.id, name: title(of: node), path: Paths.human(full), size: node.size, dir: node.isFolder,
            mtime: node.isFolder ? nil : node.modified, locked: rules.lockReason(full) ?? rules.loginLock(full, hasLogins: node.hasLogins) ?? online)
    }

    private func arcs(_ node: Node, total: Int64, depth: Int) -> [Item] {
        guard depth < 4 else { return [] }
        return node.kids.filter { Double($0.size) >= Double(total) * 0.003 }.map { kid in
            var item = describe(kid)
            item.kids = arcs(kid, total: total, depth: depth + 1)
            return item
        }
    }

    func view(_ id: Int?) throws -> FolderView {
        let node = try id.map(find) ?? top
        let hidden = node.kids.dropFirst(Self.listLimit)

        var crumbs: [FolderView.Crumb] = []
        var at: Node? = node
        while let current = at {
            crumbs.insert(.init(id: current.id, name: title(of: current)), at: 0)
            at = current.parent
        }

        return FolderView(
            node: describe(node),
            crumbs: crumbs,
            list: node.kids.prefix(Self.listLimit).map(describe),
            rest: .init(size: node.smallSize + hidden.reduce(0) { $0 + $1.size }, count: node.smallCount + hidden.count),
            arcs: arcs(node, total: node.size, depth: 0))
    }

    func cleanup() -> [Item] {
        var found: [Item] = []
        func visit(_ node: Node, _ full: String) {
            guard node.size >= Self.cleanupMinimum else { return }
            if node.parent != nil, let hint = rules.suggestion(name: node.name, isFolder: node.isFolder, path: full) {
                var item = describe(node)
                // Never offer something locked as an easy win.
                item.group = item.locked == nil ? hint.group : .app
                item.note = hint.group == .app ? hint.note : item.locked ?? hint.note
                found.append(item)
            } else {
                for kid in node.kids { visit(kid, Paths.join(full, kid.name)) }
            }
        }
        visit(top, root)
        return found.sorted { $0.size > $1.size }
    }

    func suggestions(now: Date = Date()) -> [Item] {
        var found: [Item] = []
        for place in Suggestions.places {
            let folder = place.isEmpty ? rules.home : Paths.join(rules.home, place)
            guard let parent = node(at: folder) else { continue }
            let folderNames = Set(parent.kids.filter(\.isFolder).map(\.name))
            for kid in parent.kids where kid.size >= Suggestions.minimumSize {
                var item = describe(kid)
                guard item.locked == nil,
                      rules.suggestion(name: kid.name, isFolder: kid.isFolder, path: item.path) == nil,
                      let reason = Suggestions.reason(
                          name: kid.name, isFolder: kid.isFolder, lastChanged: kid.newest > 0 ? kid.newest : kid.modified,
                          folderNames: folderNames, now: now)
                else { continue }
                item.reason = reason
                found.append(item)
            }
        }
        return Array(found.sorted { $0.size > $1.size }.prefix(Suggestions.limit))
    }

    private func node(at path: String) -> Node? {
        let start = Paths.human(root)
        guard Paths.inside(path, start) || start == "/" else { return nil }
        var node = top
        for part in path.dropFirst(start.count).split(separator: "/") {
            guard let next = node.kids.first(where: { $0.name == String(part) }) else { return nil }
            node = next
        }
        return node
    }

    /// Finds folders, and files of 1 MB or more, by name.
    func search(_ text: String) -> [Item] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return nodes.values
            .filter { $0.parent != nil && $0.name.range(of: query, options: .caseInsensitive) != nil }
            .sorted { $0.size > $1.size }
            .prefix(100)
            .map(describe)
    }

    /// What the AI gets to look at: names only, never what is in a file.
    func clues(_ id: Int) throws -> (name: String, isFolder: Bool, contains: [String]) {
        let node = try find(id)
        guard node.isFolder, !node.hasOnlineOnly else { return (node.name, node.isFolder, []) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path(of: node))) ?? []
        return (node.name, true, Array(names.filter { $0 != ".DS_Store" && $0 != "node_modules" }.sorted().prefix(12)))
    }

    func biggest() -> [Item] {
        nodes.values
            .filter { !$0.isFolder && $0.size >= Self.biggestMinimum }
            .sorted { $0.size > $1.size }
            .prefix(200)
            .map(describe)
    }

    func item(_ id: Int) throws -> ScannedItem {
        let node = try find(id)
        return ScannedItem(path: path(of: node), inode: node.inode, device: node.device, size: node.size)
    }

    func itemForTrash(_ id: Int) throws -> ScannedItem {
        if let reason = describe(try find(id)).locked { throw Failure(reason) }
        return try item(id)
    }

    /// Why this item holds work saved nowhere else, or nil.
    func unsavedWork(_ id: Int) async throws -> String? {
        let node = try find(id)
        var repos: [String] = []
        func look(_ folder: Node, _ full: String) {
            if folder.isRepo { repos.append(full) }
            for kid in folder.kids where kid.isFolder && kid.name != ".git" && kid.name != "node_modules" {
                look(kid, Paths.join(full, kid.name))
            }
        }
        let full = Paths.human(path(of: node))
        look(node, full)
        return await UnsavedWork.reason(path: full, repos: repos, home: rules.home)
    }

    func remove(_ id: Int) throws {
        let node = try find(id)
        guard let parent = node.parent else { throw Failure("Cannot remove the scan root.") }
        parent.kids.removeAll { $0 === node }
        var at: Node? = parent
        while let current = at {
            current.size -= node.size
            current.kids.sort { $0.size > $1.size }
            at = current.parent
        }
        func forget(_ item: Node) {
            nodes[item.id] = nil
            item.kids.forEach(forget)
        }
        forget(node)
    }
}
