import SwiftUI

@main
struct ClearoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // This must run before anything reads the disk.
        CloudGuard.turnOn()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: appDelegate.state, app: appDelegate)
        } label: {
            Image(nsImage: MenuIcon.image)
            Text(appDelegate.state.freeText)
        }
        .menuBarExtraStyle(.menu)
    }
}
