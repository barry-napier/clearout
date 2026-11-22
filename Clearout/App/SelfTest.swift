#if DEBUG
import AppKit
import WebKit

/// Clicks through the real window. Debug builds only.
///
///     Clearout --selftest OUTPUT_FOLDER [FAKE_HOME]
///
/// It moves things to the Trash only inside a fake home, never in your real one.
@MainActor
final class SelfTest {
    let home: String
    private let output: URL
    private let isFake: Bool

    private init(output: String, fakeHome: String?) {
        self.output = URL(fileURLWithPath: output)
        home = fakeHome ?? NSHomeDirectory()
        isFake = Paths.real(home) != Paths.real(NSHomeDirectory())
    }

    static func fromArguments() -> SelfTest? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--selftest"), args.count > index + 1 else { return nil }
        return SelfTest(output: args[index + 1], fakeHome: args.count > index + 2 ? args[index + 2] : nil)
    }

    func run(_ view: WKWebView) {
        Task {
            do {
                try await steps(view)
                print("SELFTEST PASS")
            } catch {
                print("SELFTEST FAIL \(error)")
            }
            fflush(stdout)
            exit(0)
        }
    }

    private func js(_ view: WKWebView, _ code: String) async throws -> String {
        let value = try await view.callAsyncJavaScript(code, arguments: [:], in: nil, contentWorld: .page)
        return value as? String ?? ""
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private func wait(_ view: WKWebView, for condition: String, seconds: Int) async throws {
        for _ in 0..<(seconds * 2) {
            if try await js(view, "return (\(condition)) ? 'yes' : 'no'") == "yes" { return }
            try await pause(0.5)
        }
        let state = try await js(view, "return JSON.stringify({ tab, picks: picks.size, clicks: window.clicks, toast: document.querySelector('#toast').innerText })")
        throw Failure("Timed out: \(condition) \(state)")
    }

    private func picture(_ view: WKWebView, _ name: String) async throws {
        try await pause(1.2)
        let image = try await view.takeSnapshot(configuration: nil)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw Failure("No picture") }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }

    private func save(_ view: WKWebView, _ action: String) async throws {
        let text = try await js(view, "return JSON.stringify(await api('\(action)'))")
        try Data(text.utf8).write(to: output.appendingPathComponent(action + ".json"))
    }

    private func steps(_ view: WKWebView) async throws {
        try await pause(2)
        _ = try await js(view, """
            window.problems = [];
            window.clicks = [];
            for (const type of ['click', 'keydown']) addEventListener(type, (event) => {
                window.clicks.push(`${event.isTrusted ? 'person' : 'test'} ${type} ${event.target.id || event.target.dataset?.tab || event.target.textContent.trim().slice(0, 24)}`);
            }, true);
            addEventListener('error', (event) => window.problems.push(event.message));
            addEventListener('unhandledrejection', (event) => window.problems.push(String(event.reason)));
            """)
        try await picture(view, "start")
        _ = try await js(view, "document.querySelector('#scan-home').click()")
        try await wait(view, for: "!document.querySelector('#results').hidden", seconds: 420)
        try await pause(8) // time for the AI
        try await picture(view, "home")
        view.window?.setContentSize(NSSize(width: 800, height: 600))
        try await picture(view, "small")
        view.window?.setContentSize(NSSize(width: 1360, height: 880))
        for tab in ["smart", "map"] {
            _ = try await js(view, "document.querySelector('[data-tab=\(tab)]').click()")
            try await picture(view, tab)
        }
        _ = try await js(view, "const box = document.querySelector('#search'); box.value = 'node'; box.dispatchEvent(new Event('input'))")
        try await pause(2)
        try await picture(view, "search")
        for action in ["status", "view", "cleanup", "biggest", "suggestions"] { try await save(view, action) }
        _ = try await js(view, "document.querySelector('[data-tab=cleanup]').click()")
        try await picture(view, "cleanup")
        let problems = try await js(view, "return window.problems.join('; ')")
        guard problems.isEmpty else { throw Failure(problems) }
        print("AI labels: " + (try await js(view, "return JSON.stringify([...about.values()].filter(Boolean).map((a) => a.label))")))

        guard isFake else { return }
        _ = try await js(view, "document.querySelector('#cleanup [data-pick]').click(); document.querySelector('#pile-review').click()")
        try await picture(view, "confirm")
        try await wait(view, for: "document.querySelector('#confirm').open", seconds: 30)
        _ = try await js(view, "document.querySelector('#move').click()")
        try await wait(view, for: "!document.querySelector('#toast').hidden", seconds: 30)
        print(try await js(view, "return document.querySelector('#toast').innerText"))
        print("clicks: " + (try await js(view, "return JSON.stringify(window.clicks)")))
        try await picture(view, "moved")
    }
}
#endif
