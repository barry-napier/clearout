import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppState {
    private(set) var free: Int64 = 0
    private(set) var hasFullAccess = false
    private(set) var opensAtLogin = false

    var freeText: String {
        free < 100_000_000_000
            ? String(format: "%.1f GB", Double(free) / 1e9)
            : "\(free / 1_000_000_000) GB"
    }

    var isLow: Bool { free < 20_000_000_000 }

    func refresh() {
        if let space = DiskSpace.read(NSHomeDirectory()) { free = space.free }
        hasFullAccess = Permissions.hasFullDiskAccess
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }
}
