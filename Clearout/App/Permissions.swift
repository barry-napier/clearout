import AppKit

/// Full Disk Access helpers.
enum Permissions {
    /// Only apps with Full Disk Access can open this file. Nothing is read from it.
    static var hasFullDiskAccess: Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
