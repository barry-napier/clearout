import AppKit
import UniformTypeIdentifiers
import WebKit

/// The HTML, CSS and JS inside the window. It has no server and no network.
@MainActor
final class WebPage: NSObject {
    let view: WKWebView
    private static let origin = "clearout"
    private static let host = "app"

    init(engine: Engine) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(BundledFiles(), forURLScheme: Self.origin)
        config.userContentController.addScriptMessageHandler(
            Bridge(engine: engine, scheme: Self.origin, host: Self.host), contentWorld: .page, name: "clearout")
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1360, height: 880), configuration: config)
        super.init()
        view.underPageBackgroundColor = NSColor(srgbRed: 17 / 255, green: 22 / 255, blue: 28 / 255, alpha: 1)
        view.navigationDelegate = self
        view.load(URLRequest(url: URL(string: "\(Self.origin)://\(Self.host)/index.html")!))
    }
}

extension WebPage: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(action.request.url?.scheme == Self.origin ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

/// Carries requests from the page to the engine.
@MainActor
private final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    private let engine: Engine
    private let scheme: String
    private let host: String

    init(engine: Engine, scheme: String, host: String) {
        self.engine = engine
        self.scheme = scheme
        self.host = host
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == scheme, origin.host == host,
              let request = message.body as? [String: Any], let action = request["action"] as? String
        else { return (nil, "That request was not allowed.") }
        do {
            return (try await engine.handle(action, request["body"] as? [String: Any] ?? [:]), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}

/// Serves only the three page files inside the app.
@MainActor
private final class BundledFiles: NSObject, WKURLSchemeHandler {
    private static let allowed: Set<String> = ["index.html", "style.css", "app.js"]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, Self.allowed.contains(url.lastPathComponent),
              let file = Bundle.main.url(forResource: url.lastPathComponent, withExtension: nil),
              let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
