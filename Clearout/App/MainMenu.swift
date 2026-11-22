import AppKit

/// The menus at the top of the screen while the window is open.
@MainActor
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        func menu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            holder.submenu = submenu
            main.addItem(holder)
        }
        func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
            NSMenuItem(title: title, action: action, keyEquivalent: key)
        }

        let open = item("Open Clearout", #selector(AppDelegate.showMain), "o")
        open.target = target
        menu("Clearout", [
            open,
            item("Hide Clearout", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit Clearout", #selector(NSApplication.terminate(_:)), "q"),
        ])
        menu("Edit", [
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        menu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        return main
    }
}
