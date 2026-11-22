import AppKit

/// Does what the page asks: scan, show, move to the Trash.
@MainActor
final class Engine {
    private final class Session {
        enum State: String, Encodable {
            case scanning, ready, failed
        }

        let id: Int
        let root: String
        let scanner: Scanner
        let started = Date()
        var state = State.scanning
        var map: DiskMap?
        var summary: ScanSummary?
        var seconds: Double?
        var unseen: Int64?
        var error: String?

        init(id: Int, root: String, home: String) {
            self.id = id
            self.root = root
            scanner = Scanner(root: root, home: home)
        }
    }

    private struct Status: Encodable {
        struct Scan: Encodable {
            let id: Int
            let root: String
            let state: Session.State
            let progress: ScanProgress
            let result: ScanSummary?
            let seconds: Double?
            let unseen: Int64?
            let error: String?
        }

        let home: String
        let free: Int64
        let total: Int64
        let fullAccess: Bool
        let aiNote: String?
        let scan: Scan?
    }

    let home: String
    private let rules: Rules
    private var session: Session?
    private var lastID = 0

    init(home: String) {
        self.home = Paths.real(home) ?? home
        rules = Rules(home: self.home)
    }

    /// Returns JSON for the page.
    func handle(_ action: String, _ body: [String: Any]) async throws -> String {
        switch action {
        case "status":
            return try json(status())
        case "scan":
            return try json(["scan": startScan(body["where"] as? String ?? "")])
        case "stop":
            stopScan()
        case "access":
            Permissions.openFullDiskAccessSettings()
        case "open-trash":
            openTrash()
        case "view":
            return try await json(readyMap(body).view(body["id"] as? Int))
        case "cleanup":
            return try await json(readyMap(body).cleanup())
        case "biggest":
            return try await json(readyMap(body).biggest())
        case "suggestions":
            let map = try readyMap(body)
            var picks = await map.suggestions()
            for index in picks.indices {
                picks[index].locked = try await map.unsavedWork(picks[index].id)
            }
            return try json(picks.filter { $0.locked == nil } + picks.filter { $0.locked != nil })
        case "check":
            if let reason = try await readyMap(body).unsavedWork(requiredID(body)) {
                return try json(["reason": reason])
            }
        case "search":
            return try await json(readyMap(body).search(body["query"] as? String ?? ""))
        case "explain":
            let clues = try await readyMap(body).clues(requiredID(body))
            if let answer = await Explainer.explain(name: clues.name, isFolder: clues.isFolder, contains: clues.contains) {
                return try json(answer)
            }
        case "reveal":
            let item = try await readyMap(body).item(requiredID(body))
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Paths.human(item.path))])
        case "trash":
            return try await json(["size": moveToTrash(readyMap(body), requiredID(body))])
        default:
            throw Failure("Clearout does not know that action.")
        }
        return "{}"
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: home + "/.Trash", isDirectory: true))
    }

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func requiredID(_ body: [String: Any]) throws -> Int {
        guard let id = body["id"] as? Int else { throw Failure("No item was picked.") }
        return id
    }

    private func readyMap(_ body: [String: Any]) throws -> DiskMap {
        guard let session, let map = session.map, body["scan"] as? Int == session.id else {
            throw Failure("This scan is old. Scan again.")
        }
        return map
    }

    private func status() -> Status {
        let space = DiskSpace.read(home)
        let scan = session.map {
            Status.Scan(
                id: $0.id, root: Paths.human($0.root), state: $0.state, progress: $0.scanner.progress,
                result: $0.summary, seconds: $0.seconds, unseen: $0.unseen, error: $0.error)
        }
        return Status(
            home: home, free: space?.free ?? 0, total: space?.total ?? 1,
            fullAccess: Permissions.hasFullDiskAccess,
            aiNote: Explainer.unavailableMessage, scan: scan)
    }

    /// 0 means the person closed the folder picker.
    private func startScan(_ place: String) throws -> Int {
        let root: String
        switch place {
        case "home":
            root = home
        case "disk":
            root = Paths.data
        case "choose":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.prompt = "Scan"
            guard panel.runModal() == .OK, let url = panel.url else { return 0 }
            let picked = url.path(percentEncoded: false)
            guard let real = Paths.real(picked) else { throw Failure("Clearout cannot open that folder.") }
            root = real
        default:
            throw Failure("Pick a place to scan.")
        }

        stopScan()
        lastID += 1
        let current = Session(id: lastID, root: root, home: home)
        session = current
        Task { await finish(current) }
        return current.id
    }

    private func finish(_ current: Session) async {
        do {
            let output = try await current.scanner.run()
            if current.root == Paths.data, let used = await DiskSpace.usedOnDataVolume() {
                current.unseen = max(0, used - output.summary.bytes)
            }
            current.map = DiskMap(output, rules: rules)
            current.summary = output.summary
            current.seconds = Date().timeIntervalSince(current.started)
            current.state = .ready
        } catch {
            current.error = error is CancellationError ? "The scan stopped." : error.localizedDescription
            current.state = .failed
        }
    }

    private func stopScan() {
        session?.scanner.cancel()
        session = nil
    }

    private func moveToTrash(_ map: DiskMap, _ id: Int) async throws -> Int64 {
        let item = try await map.itemForTrash(id)
        if let reason = try await map.unsavedWork(id) { throw Failure(reason) }
        let rules = rules
        try await Task.detached {
            let path = try rules.checkBeforeTrash(item)
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        }.value
        // The move worked. A problem updating the map must not report it as failed.
        try? await map.remove(id)
        return item.size
    }
}
