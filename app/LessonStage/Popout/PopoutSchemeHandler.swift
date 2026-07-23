import Foundation
import WebKit

/// Serves the bundled Vue popout build over a custom scheme.
///
/// A custom scheme rather than `file://` because file URLs put the webview in
/// a unique opaque origin, where module scripts and `fetch` are blocked by
/// CORS. Owning the scheme means owning the response headers — which is also
/// how the cross-origin call to solver-service gets solved later, and the only
/// route to cross-origin isolation if the popout ever needs `SharedArrayBuffer`.
final class PopoutSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lesson-popout"

    /// The entry point the webview loads.
    static let entryURL = URL(string: "\(scheme)://popout/index.html")!

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(PopoutError.badRequest)
            return
        }

        // Vite emits relative asset URLs, and Xcode flattens bundled resources,
        // so the last path component is the lookup key either way.
        var name = url.lastPathComponent
        if name.isEmpty || name == "/" { name = "index.html" }

        guard let fileURL = Bundle.main.url(forResource: name, withExtension: nil),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(PopoutError.notFound(name))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: name),
                "Content-Length": String(data.count),
                // The bundle is local and fixed; nothing here is revalidated.
                "Cache-Control": "no-store",
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Every response above is served synchronously and completed before
        // returning, so there is never an in-flight task to cancel. This stops
        // being true the moment anything is served asynchronously — at which
        // point a cancelled-task set is required, because calling back into a
        // stopped task traps.
    }

    private static func mimeType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json"
        case "wasm": "application/wasm"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }
}

enum PopoutError: LocalizedError {
    case badRequest
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .badRequest: "Malformed popout request."
        case .notFound(let name): "Popout resource not bundled: \(name)"
        }
    }
}
