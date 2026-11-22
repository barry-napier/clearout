import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private(set) var engine = Engine(home: NSHomeDirectory())

    private var mainWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var page: WebPage?
    private var spaceTimer: Timer?
    #if DEBUG
    private var selfTest: SelfTest?
    #endif

    private static let welcomeDoneKey = "welcomeDone"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(target: self)
        state.refresh()
        spaceTimer = Timer.scheduledTimer(
            timeInterval: 10, target: self, selector: #selector(refreshState), userInfo: nil, repeats: true)

        #if DEBUG
        if let test = SelfTest.fromArguments() {
            selfTest = test
            engine = Engine(home: test.home)
            showMain()
            if let page { test.run(page.view) }
            return
        }
        #endif

        if !UserDefaults.standard.bool(forKey: Self.welcomeDoneKey) {
            showWelcome()
        } else if !Self.launchedAtLogin {
            showMain()
        }
    }

    /// At login, only the menu bar icon should appear.
    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if welcomeWindow?.isVisible == true {
            showWelcome()
        } else {
            showMain()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func refreshState() {
        state.refresh()
    }

    @objc func showMain() {
        if mainWindow == nil {
            let page = WebPage(engine: engine)
            let window = Windows.make(title: "Clearout", size: NSSize(width: 1360, height: 880))
            window.contentView = page.view
            window.titleVisibility = .hidden
            window.contentMinSize = NSSize(width: 760, height: 520)
            window.setFrameAutosaveName("Dashboard")
            window.delegate = self
            self.page = page
            mainWindow = window
        }
        // A Dock icon and Command-Tab, only while the window is open.
        NSApp.setActivationPolicy(.regular)
        Windows.present(mainWindow!)
    }

    func showWelcome() {
        let view = WelcomeView(state: state) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.welcomeDoneKey)
            self?.welcomeWindow?.close()
            self?.showMain()
        }
        if welcomeWindow == nil {
            welcomeWindow = Windows.make(title: "Welcome to Clearout", size: NSSize(width: 520, height: 390))
        }
        welcomeWindow?.contentView = NSHostingView(rootView: view)
        state.refresh()
        Windows.present(welcomeWindow!)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
