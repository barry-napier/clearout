import Foundation

/// Stops code that is saved nowhere else from going to the Trash.
///
/// It asks git, and only to look: no hooks, no network, no writes. A project's own
/// settings can make "git status" run programs, so those projects are not asked.
/// When it cannot tell, the answer is "not saved".
enum UnsavedWork {
    private static let maximumRepos = 40
    private static let secretExamples = ["example", "sample", "template"]

    /// A plain-words reason, or nil. `repos` are the projects inside the item.
    static func reason(path: String, repos: [String], home: String) async -> String? {
        await Task.detached { check(path: path, repos: repos, home: home) }.value
    }

    private static func check(path: String, repos: [String], home: String) -> String? {
        guard Paths.inside(path, home), path != home else { return nil }
        let rel = path.dropFirst(home.count + 1)
        // The only unlocked places in here are caches.
        if rel.hasPrefix("Library/") || rel.hasPrefix(".") { return nil }
        // Package folders are downloaded again, and are full of other people's projects.
        if rel.split(separator: "/").contains("node_modules") { return nil }
        guard repos.count <= maximumRepos else { return "Too many code projects to check. Pick smaller folders." }

        for repo in repos {
            if let problem = problem(inRepo: repo) {
                return repo == path ? problem : "\(Paths.name(repo)): \(problem)"
            }
        }
        // Part of a project: only changes inside that part would be lost.
        if !repos.contains(path), let repo = enclosingRepo(path, home: home) {
            guard let changes = changes(inRepo: repo, at: path) else { return "Clearout cannot check if this code is saved." }
            if !changes.isEmpty { return "It has code changes that are not saved." }
        }
        return nil
    }

    private static func problem(inRepo repo: String) -> String? {
        let unknown = "Clearout cannot check if this code is saved."
        guard let remotes = git(repo, ["remote"]) else { return unknown }
        if remotes.isEmpty { return "This code has no online copy." }
        guard let changes = changes(inRepo: repo, at: repo) else { return unknown }
        if !changes.isEmpty { return "It has \(count(changes.count, "changed file")) not saved." }
        guard let commits = git(repo, ["rev-list", "HEAD", "--branches", "--not", "--remotes"]) else { return unknown }
        if !commits.isEmpty { return "It has \(count(commits.count, "save")) not uploaded." }
        guard let parked = git(repo, ["stash", "list", "--format=%H", "--no-show-signature"]) else { return unknown }
        if !parked.isEmpty { return "It has \(count(parked.count, "parked change")) not uploaded." }

        // git skips these on purpose, so they exist only on this Mac.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: repo) else { return unknown }
        let hasSecrets = names.contains { name in
            (name == ".env" || name.hasPrefix(".env.")) && !secretExamples.contains { name.contains($0) }
        }
        return hasSecrets ? "It has a private settings file (.env). That is only on this Mac." : nil
    }

    private static func count(_ number: Int, _ word: String) -> String {
        "\(number) \(word)\(number == 1 ? "" : "s")"
    }

    private static func enclosingRepo(_ path: String, home: String) -> String? {
        var folder = Paths.parent(path)
        while folder != home, Paths.inside(folder, home) {
            if Paths.info(folder + "/.git") != nil { return folder }
            folder = Paths.parent(folder)
        }
        return nil
    }

    private static func changes(inRepo repo: String, at path: String) -> [String]? {
        // "filter" settings from the project itself would run a program during status.
        guard let settings = git(repo, ["config", "--show-scope", "--name-only", "--list"]) else { return nil }
        let unsafe = settings.contains { line in
            (line.hasPrefix("local") || line.hasPrefix("worktree")) && line.lowercased().contains("filter.")
        }
        guard !unsafe else { return nil }
        let target = path == repo ? "." : String(path.dropFirst(repo.count + 1))
        return git(repo, ["status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=all", "--", target])
    }

    /// Output lines, or nil when git failed.
    private static func git(_ repo: String, _ arguments: [String]) -> [String]? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = [
            "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "log.showSignature=false",
            "--literal-pathspecs", "-C", repo,
        ] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        environment["GIT_ALLOW_PROTOCOL"] = ""
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }

        let stop = DispatchWorkItem { task.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: stop)
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        stop.cancel()
        guard task.terminationStatus == 0 else { return nil }
        return String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
