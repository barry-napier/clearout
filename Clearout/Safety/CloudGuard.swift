import Darwin

/// iCloud keeps some folders only online. Just listing one makes macOS download it,
/// which fills the disk. Clearout switches that off for the whole process at launch.
enum CloudGuard {
    // IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, ..._OFF
    private static let type: Int32 = 3
    private static let process: Int32 = 0
    private static let off: Int32 = 1

    static func turnOn() {
        _ = setiopolicy_np(type, process, off)
    }

    /// Scans refuse to start unless this is true.
    static var isOn: Bool {
        getiopolicy_np(type, process) == off
    }

    /// True for a file or folder that is only online (SF_DATALESS).
    static func isOnlineOnly(_ info: stat) -> Bool {
        info.st_flags & 0x4000_0000 != 0
    }
}
