import AppKit

/// Makes and shows plain windows for a menu bar app.
@MainActor
enum Windows {
    static func make(title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        // Clearout is always dark, like its screens.
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: 17 / 255, green: 22 / 255, blue: 28 / 255, alpha: 1)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    static func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
