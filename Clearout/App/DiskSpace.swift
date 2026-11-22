import Foundation

struct DiskSpace {
    let free: Int64
    let total: Int64

    static func read(_ path: String) -> DiskSpace? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let block = Int64(info.f_bsize)
        return DiskSpace(free: Int64(info.f_bavail) * block, total: Int64(info.f_blocks) * block)
    }

    /// statfs counts every volume that shares the disk, so ask df for this one alone.
    static func usedOnDataVolume() async -> Int64? {
        await Task.detached {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/bin/df")
            task.arguments = ["-k", Paths.data]
            task.standardOutput = pipe
            guard (try? task.run()) != nil else { return nil }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()
            let lines = output.split(separator: "\n")
            guard lines.count > 1 else { return nil }
            let cells = lines[1].split(separator: " ")
            guard cells.count > 2, let used = Int64(cells[2]) else { return nil }
            return used * 1024
        }.value
    }
}
