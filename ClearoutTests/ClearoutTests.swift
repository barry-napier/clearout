import XCTest

final class ClearoutTests: XCTestCase {
    private var home = ""

    override func setUpWithError() throws {
        CloudGuard.turnOn()
        let folder = NSTemporaryDirectory() + "clearout-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        home = try XCTUnwrap(Paths.real(folder))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(atPath: home)
    }

    private func put(_ name: String, bytes: Int = 10) throws {
        let path = home + "/" + name
        try FileManager.default.createDirectory(atPath: Paths.parent(path), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: URL(fileURLWithPath: path))
    }

    private func scan() async throws -> DiskMap {
        DiskMap(try await Scanner(root: home, home: home).run(), rules: Rules(home: home))
    }

    private func child(_ name: String, of id: Int? = nil, in map: DiskMap) async throws -> Item {
        let list = try await map.view(id).list
        return try XCTUnwrap(list.first { $0.name == name })
    }

    func testRiskyPathsAreLocked() {
        let rules = Rules(home: home)
        for item in ["", "Documents", "documents", "Library", "library/Keychains", ".ssh/id", ".cache", "Library/Caches",
                     "Library/Caches/com.apple.test", "Library/Caches/../Keychains", "Library/Application Support/Any",
                     "Pictures/My.photoslibrary", "code/.git", "code/.git/objects", "My.app/Contents",
                     "Music/Music", "Parallels/Windows.pvm"] {
            XCTAssertNotNil(rules.lockReason(item.isEmpty ? home : home + "/" + item), item)
        }
        for item in ["/System", "/Applications/Any.app", home + "-else/file"] {
            XCTAssertNotNil(rules.lockReason(item), item)
        }
    }

    func testSafePathsAreOpen() {
        let rules = Rules(home: home)
        for item in ["Downloads/a.dmg", "code/node_modules", "Library/Caches/tool", ".npm/_cacache"] {
            XCTAssertNil(rules.lockReason(home + "/" + item), item)
            XCTAssertNil(rules.lockReason(Paths.data + home + "/" + item), item)
        }
    }

    func testICloudFoldersAreLocked() throws {
        try put("Library/Mobile Documents/com~apple~CloudDocs/Documents/marker")
        let rules = Rules(home: home)
        XCTAssertNotNil(rules.lockReason(home + "/Documents/old/node_modules"))
        XCTAssertNotNil(rules.lockReason(home + "/Desktop/photo.png"))
        XCTAssertNil(rules.lockReason(home + "/Downloads/a.dmg"))
    }

    func testCloudGuardIsOn() {
        XCTAssertTrue(CloudGuard.isOn)
    }

    func testOnlineOnlyFlag() {
        var info = stat()
        XCTAssertFalse(CloudGuard.isOnlineOnly(info))
        info.st_flags = 0x4000_0020
        XCTAssertTrue(CloudGuard.isOnlineOnly(info))
    }

    func testHardLinksCountOnceAndShortcutsAreNotFollowed() async throws {
        try put("work/file.bin", bytes: 2_000_000)
        try FileManager.default.linkItem(atPath: home + "/work/file.bin", toPath: home + "/work/twin.bin")
        try FileManager.default.createSymbolicLink(atPath: home + "/shortcut", withDestinationPath: "/System")
        let total = try await scan().view(nil).node.size
        XCTAssertGreaterThanOrEqual(total, 2_000_000)
        XCTAssertLessThan(total, 2_200_000)
    }

    func testOddNamesSurvive() async throws {
        let names = ["<img src=x>.bin", "Sam’s café 🧹.bin", "two\nlines.bin", "-dash.bin"]
        for name in names { try put(name, bytes: 1_100_000) }
        let found = try await scan().view(nil).list.map(\.name)
        XCTAssertEqual(Set(found), Set(names))
    }

    func testCleanupFindsNodeModules() async throws {
        try put("project/package.json")
        try put("project/node_modules/big.bin", bytes: 22_000_000)
        let found = await (try scan()).cleanup()
        XCTAssertEqual(found.map(\.name), ["node_modules"])
        XCTAssertEqual(found.first?.group, .again)
    }

    func testRemoveFixesTotals() async throws {
        try put("project/big/file.bin", bytes: 3_000_000)
        let map = try await scan()
        let before = try await map.view(nil).node.size
        let project = try await child("project", in: map)
        let big = try await child("big", of: project.id, in: map)
        try await map.remove(big.id)
        let after = try await map.view(nil).node.size
        XCTAssertEqual(after, before - big.size)
    }

    func testTrashRefusesLockedItems() async throws {
        try put("Library/secret.bin", bytes: 2_000_000)
        let map = try await scan()
        let library = try await child("Library", in: map)
        do {
            _ = try await map.itemForTrash(library.id)
            XCTFail("A locked item got through")
        } catch {}
    }

    func testTrashRefusesReplacedItems() async throws {
        try put("work/file.bin")
        let map = try await scan()
        let item = try await map.itemForTrash(child("work", in: map).id)
        XCTAssertNoThrow(try Rules(home: home).checkBeforeTrash(item))
        try FileManager.default.moveItem(atPath: home + "/work", toPath: home + "/old")
        try put("work/other.bin")
        XCTAssertThrowsError(try Rules(home: home).checkBeforeTrash(item))
    }

    func testTrashRefusesRedirectedPaths() async throws {
        try put("project/file.bin", bytes: 2_000_000)
        let map = try await scan()
        let project = try await child("project", in: map)
        let item = try await map.itemForTrash(child("file.bin", of: project.id, in: map).id)
        try FileManager.default.moveItem(atPath: home + "/project", toPath: home + "/real")
        try FileManager.default.createSymbolicLink(atPath: home + "/project", withDestinationPath: home + "/real")
        XCTAssertThrowsError(try Rules(home: home).checkBeforeTrash(item))
    }

    private func makeOld(_ name: String, days: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -days * 86400)], ofItemAtPath: home + "/" + name)
    }

    func testSmartPicksFindForgottenThings() async throws {
        try put("forgotten/big.bin", bytes: 51_000_000)
        try makeOld("forgotten/big.bin", days: 200)
        try put("forgotten/.DS_Store") // looking in Finder is not a change
        try put("active/big.bin", bytes: 51_000_000)
        try put("trip.zip", bytes: 51_000_000)
        try put("trip/photo.jpg")
        let picks = await (try scan()).suggestions()
        XCTAssertEqual(Set(picks.map(\.name)), ["forgotten", "trip.zip"])
        XCTAssertEqual(picks.first { $0.name == "forgotten" }?.reason, "Not changed for 6 months.")
    }

    func testSmartPicksNeverOfferLockedThings() async throws {
        try put("Library/Mobile Documents/com~apple~CloudDocs/Documents/marker")
        for name in ["Documents/old.mov", "Pictures/Old.photoslibrary/photo.bin"] {
            try put(name, bytes: 51_000_000)
            try makeOld(name, days: 900)
        }
        let picks = await (try scan()).suggestions()
        XCTAssertEqual(picks.map(\.name), [])
    }

    func testSearchFindsNames() async throws {
        try put("Holiday Photos/photo.bin")
        let found = await (try scan()).search("holiday")
        XCTAssertEqual(found.map(\.name), ["Holiday Photos"])
    }

    private func git(_ folder: String, _ arguments: String...) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = [
            "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-C", home + "/" + folder,
        ] + arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        XCTAssertEqual(task.terminationStatus, 0, arguments.joined(separator: " "))
    }

    /// A project with one save, uploaded to a fake "online" folder.
    private func makeUploadedProject() throws {
        try put("project/src/code.txt")
        try put("online/marker")
        try git("online", "init", "--bare", "remote.git")
        try git("project", "init", "-b", "main")
        try git("project", "add", ".")
        try git("project", "commit", "-m", "first")
        try git("project", "remote", "add", "origin", home + "/online/remote.git")
        try git("project", "push", "origin", "main")
    }

    private func unsaved(_ name: String, inside parent: String? = nil) async throws -> String? {
        let map = try await scan()
        var parentID: Int?
        if let parent { parentID = try await child(parent, in: map).id }
        let item = try await child(name, of: parentID, in: map)
        return try await map.unsavedWork(item.id)
    }

    func testUploadedProjectCanGo() async throws {
        try makeUploadedProject()
        let reason = try await unsaved("project")
        XCTAssertNil(reason)
    }

    func testProjectWithNoOnlineCopyStays() async throws {
        try put("project/code.txt")
        try git("project", "init", "-b", "main")
        let reason = try await unsaved("project")
        XCTAssertEqual(reason, "This code has no online copy.")
    }

    func testChangedProjectStays() async throws {
        try makeUploadedProject()
        try put("project/src/new.txt")
        let whole = try await unsaved("project")
        XCTAssertEqual(whole, "It has 1 changed file not saved.")
        let part = try await unsaved("src", inside: "project")
        XCTAssertEqual(part, "It has code changes that are not saved.")
    }

    func testProjectWithSavesNotUploadedStays() async throws {
        try makeUploadedProject()
        try put("project/src/new.txt")
        try git("project", "add", ".")
        try git("project", "commit", "-m", "second")
        let reason = try await unsaved("project")
        XCTAssertEqual(reason, "It has 1 save not uploaded.")
    }

    func testProjectWithParkedChangesStays() async throws {
        try makeUploadedProject()
        try put("project/src/code.txt", bytes: 20)
        try git("project", "stash")
        let reason = try await unsaved("project")
        XCTAssertEqual(reason, "It has 1 parked change not uploaded.")
    }

    func testProjectWithPrivateSettingsStays() async throws {
        try makeUploadedProject()
        try put("project/.env")
        try put("project/.git/info/exclude") // replaced below
        try Data(".env\n".utf8).write(to: URL(fileURLWithPath: home + "/project/.git/info/exclude"))
        let reason = try await unsaved("project")
        XCTAssertNotNil(reason)
    }

    func testFolderHoldingUnsavedProjectStays() async throws {
        try put("box/inner/code.txt")
        try git("box/inner", "init", "-b", "main")
        let reason = try await unsaved("box")
        XCTAssertEqual(reason, "inner: This code has no online copy.")
    }

    func testCheckNeverRunsProjectPrograms() async throws {
        try makeUploadedProject()
        try git("project", "config", "filter.trap.clean", "touch \(home)/ran; cat")
        try put("project/src/code.txt", bytes: 30)
        try put("project/.gitattributes")
        try Data("* filter=trap\n".utf8).write(to: URL(fileURLWithPath: home + "/project/.gitattributes"))
        let reason = try await unsaved("project")
        XCTAssertEqual(reason, "Clearout cannot check if this code is saved.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home + "/ran"))
    }

    func testCacheWithLoginsIsLocked() async throws {
        try put("Library/Caches/ms-playwright/mcp-chrome/Default/Cookies")
        try put("Library/Caches/ms-playwright/chromium/big.bin", bytes: 22_000_000)
        let map = try await scan()
        let library = try await child("Library", in: map)
        let caches = try await child("Caches", of: library.id, in: map)
        let tool = try await child("ms-playwright", of: caches.id, in: map)
        let profile = try await child("mcp-chrome", of: tool.id, in: map)
        let browser = try await child("chromium", of: tool.id, in: map)
        XCTAssertNotNil(tool.locked)
        XCTAssertNotNil(profile.locked)
        XCTAssertNil(browser.locked)
        let found = await map.cleanup()
        XCTAssertEqual(found.map(\.group), [.app])
        XCTAssertEqual(found.first?.note, tool.locked)
    }

    func testSystemCachesAreLocked() {
        let rules = Rules(home: home)
        XCTAssertNotNil(rules.lockReason(home + "/Library/Caches/GeoServices"))
        XCTAssertNotNil(rules.lockReason(home + "/Library/Caches/GeoServices/Resources"))
        XCTAssertNil(rules.lockReason(home + "/Library/Caches/GeoServicesHelper"))
    }

    func testOpenFilesSkipClearoutItself() {
        let output = "p7\ncClearout\nn/a/mine\np8\ncDia\nfcwd\nn/a/theirs\n"
        XCTAssertEqual(OpenFiles.parse(output, ignoring: 7).map(\.path), ["/a/theirs"])
    }

    func testFolderInUseStays() async throws {
        try put("café folder/file.txt")
        try put("idle/file.txt")
        let reader = Process()
        reader.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        reader.arguments = ["-f", home + "/café folder/file.txt"]
        reader.standardOutput = FileHandle.nullDevice
        try reader.run()
        defer { reader.terminate() }
        try await Task.sleep(for: .milliseconds(500))
        let files = OpenFiles()
        let busy = await files.reason(path: home + "/café folder")
        let idle = await files.reason(path: home + "/idle")
        XCTAssertEqual(busy, "tail is using this. Quit it first.")
        XCTAssertNil(idle)
    }

    func testCancelStopsTheScan() async throws {
        try put("file.bin")
        let scanner = Scanner(root: home, home: home)
        scanner.cancel()
        do {
            _ = try await scanner.run()
            XCTFail("The scan did not stop")
        } catch is CancellationError {}
    }
}
