import SwiftUI
import WebKit

/// The one long-lived `WKWebView` the popout runs in.
///
/// Kept warm and reused across popouts rather than created per tap: the first
/// load pays process spin-up and Vue's mount cost, and paying that in front of
/// a class on every tap is the failure mode this avoids.
@MainActor
final class PopoutWebViewHost: NSObject {
    static let shared = PopoutWebViewHost()

    /// Name of the JS→native message handler: `window.webkit.messageHandlers.popout`.
    private static let messageHandlerName = "popout"

    private let handler = PopoutSchemeHandler()

    private(set) lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: PopoutSchemeHandler.scheme)
        configuration.userContentController.add(self, name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.bounces = false
        return webView
    }()

    private var hasLoaded = false

    /// Load once; subsequent presentations reuse the live document.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(URLRequest(url: PopoutSchemeHandler.entryURL))
    }

    /// Native → JS. Phase 3 supplies `blockBody` and `pbn` from the PDF's
    /// Contract 5 payload; the spike sends a fixture in the same shape.
    func post(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            assertionFailure("popout payload is not JSON-serializable")
            return
        }
        webView.evaluateJavaScript("window.lessonStage.load(\(json))")
    }
}

extension PopoutWebViewHost: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        Task { @MainActor in
            guard let dict = body as? [String: Any],
                  let type = dict["type"] as? String else { return }

            switch type {
            case "ready":
                // The webview announces itself when Vue has mounted — earlier
                // than this and `window.lessonStage` does not exist yet.
                post(PopoutPayload.spikeFixture)
            default:
                break
            }
        }
    }
}

/// Payloads crossing the seam. Everything here is plain JSON by construction:
/// no live object can span the boundary.
enum PopoutPayload {
    /// One completed trick plus an opening card of the next, so trick history
    /// is non-empty on arrival and "Back a trick" has something to undo.
    static let spikeFixture: [String: Any] = [
        "kind": "hand",
        "plays": [
            ["seat": "E", "suit": "D", "rank": "K"],
            ["seat": "S", "suit": "D", "rank": "3"],
            ["seat": "W", "suit": "D", "rank": "8"],
            ["seat": "N", "suit": "D", "rank": "A"],
            ["seat": "N", "suit": "S", "rank": "A"],
        ],
    ]
}

struct PopoutWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = PopoutWebViewHost.shared.webView
        PopoutWebViewHost.shared.loadIfNeeded()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
