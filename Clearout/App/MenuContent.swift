import SwiftUI

/// The menu shown when the user clicks the Clearout menu bar icon.
struct MenuContent: View {
    let state: AppState
    let app: AppDelegate

    var body: some View {
        Text("\(state.isLow ? "🔴" : "🟢") \(state.freeText) free")
        if state.hasFullAccess {
            Text("🟢 Full Disk Access: on")
        } else {
            Text("🟡 Full Disk Access: not on")
            Button("Show Hidden Folders…") { Permissions.openFullDiskAccessSettings() }
        }
        Divider()
        Button("Open Clearout") { app.showMain() }
            .keyboardShortcut("o")
        Button("Open Trash") { app.engine.openTrash() }
        Divider()
        Toggle("Open at Login", isOn: Binding(get: { state.opensAtLogin }, set: { state.setOpensAtLogin($0) }))
        Button("Show Welcome Again") { app.showWelcome() }
        Divider()
        Button("Quit Clearout") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
