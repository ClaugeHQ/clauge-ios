import SwiftUI
import WebKit

/// Commands the live WKWebView from SwiftUI chrome (back/forward/reload).
@MainActor
final class WebController: ObservableObject {
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    var canGoBack: Bool { webView?.canGoBack ?? false }
    var canGoForward: Bool { webView?.canGoForward ?? false }
}

/// Serves proxied localhost requests through a custom scheme so the bearer token
/// reaches every same-origin subresource (WKWebView can't intercept plain http).
final class ProxySchemeHandler: NSObject, WKURLSchemeHandler {
    static let httpScheme = "claugeproxy"
    static let httpsScheme = "claugeproxys"

    var token: String?
    private let session = URLSession(configuration: .ephemeral)
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    init(token: String?) { self.token = token }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let original = urlSchemeTask.request.url,
              let upstream = Self.upstreamURL(from: original) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        var req = URLRequest(url: upstream)
        req.httpMethod = urlSchemeTask.request.httpMethod ?? "GET"
        if let headers = urlSchemeTask.request.allHTTPHeaderFields {
            for (k, v) in headers where k.lowercased() != "authorization" {
                req.setValue(v, forHTTPHeaderField: k)
            }
        }
        if let body = urlSchemeTask.request.httpBody { req.httpBody = body }
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let key = ObjectIdentifier(urlSchemeTask)
        let task = session.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.tasks[key] != nil else { return }
                self.tasks[key] = nil

                if let error {
                    urlSchemeTask.didFailWithError(error)
                    return
                }

                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 200
                var headers: [String: String] = [:]
                if let fields = http?.allHeaderFields {
                    for (k, v) in fields {
                        if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
                    }
                }
                headers["Access-Control-Allow-Origin"] = "*"

                let resp: URLResponse = HTTPURLResponse(
                    url: original,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                ) ?? URLResponse(url: original, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)

                urlSchemeTask.didReceive(resp)
                if let data { urlSchemeTask.didReceive(data) }
                urlSchemeTask.didFinish()
            }
        }
        tasks[key] = task
        task.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    static func upstreamURL(from url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch c.scheme {
        case httpScheme: c.scheme = "http"
        case httpsScheme: c.scheme = "https"
        default: break
        }
        return c.url
    }

    static func rewriteToCustomScheme(_ urlString: String) -> URL? {
        guard var c = URLComponents(string: urlString) else { return nil }
        switch c.scheme {
        case "http": c.scheme = httpScheme
        case "https": c.scheme = httpsScheme
        default: break
        }
        return c.url
    }
}

struct BrowserWebView: UIViewRepresentable {
    let url: String
    let isProxy: Bool
    let token: String?
    let consoleOpen: Bool
    let controller: WebController
    let onNav: (Bool, Bool) -> Void
    let onTitle: (String) -> Void
    let onLoading: (Bool) -> Void
    let onError: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        if isProxy {
            let handler = ProxySchemeHandler(token: token)
            config.setURLSchemeHandler(handler, forURLScheme: ProxySchemeHandler.httpScheme)
            config.setURLSchemeHandler(handler, forURLScheme: ProxySchemeHandler.httpsScheme)
            context.coordinator.schemeHandler = handler

            #if DEBUG
            let ucc = WKUserContentController()
            ucc.add(context.coordinator, name: "claugeLog")
            ucc.addUserScript(WKUserScript(
                source: Self.consoleCaptureJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
            config.userContentController = ucc
            #endif
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Theme.background)
        webView.scrollView.backgroundColor = webView.backgroundColor

        controller.webView = webView
        context.coordinator.webView = webView
        loadIfNeeded(webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadIfNeeded(webView, context: context)

        guard isProxy else { return }
        if context.coordinator.lastConsoleOpen != consoleOpen {
            context.coordinator.lastConsoleOpen = consoleOpen
            let js = consoleOpen ? Self.erudaShowJS : Self.erudaHideJS
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func loadIfNeeded(_ webView: WKWebView, context: Context) {
        if context.coordinator.didLoad { return }
        if isProxy {
            // #5: wait for the token before loading a proxied page.
            guard let token, !token.isEmpty else { return }
            guard let target = ProxySchemeHandler.rewriteToCustomScheme(url) else { return }
            context.coordinator.schemeHandler?.token = token
            context.coordinator.didLoad = true
            webView.load(URLRequest(url: target))
        } else {
            // #5: external pages load directly with no token.
            guard let real = URL(string: url) else { return }
            context.coordinator.didLoad = true
            webView.load(URLRequest(url: real))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        #if DEBUG
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "claugeLog")
        #endif
    }

    // #8: eruda console is injected only on proxied pages.
    private static let erudaShowJS = "(function(){if(window.eruda){eruda.show();return;}var s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/eruda';s.onload=function(){eruda.init();eruda.show();};document.head.appendChild(s);})();"
    private static let erudaHideJS = "if(window.eruda)eruda.hide();"
    private static let consoleCaptureJS = """
    (function(){var levels=['log','warn','error','info'];levels.forEach(function(l){var orig=console[l];console[l]=function(){try{window.webkit.messageHandlers.claugeLog.postMessage(l+': '+Array.prototype.join.call(arguments,' '));}catch(e){}orig.apply(console,arguments);};});})();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: BrowserWebView
        weak var webView: WKWebView?
        var schemeHandler: ProxySchemeHandler?
        var didLoad = false
        var lastConsoleOpen = false

        init(_ parent: BrowserWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading(true)
            parent.onError(nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
            parent.onNav(webView.canGoBack, webView.canGoForward)
            if let t = webView.title, !t.isEmpty { parent.onTitle(t) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoading(false)
            parent.onError("Couldn't load this page")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onLoading(false)
            parent.onError("Couldn't load this page")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // #10: console logging is DEBUG-only.
            #if DEBUG
            if let s = message.body as? String { print("[ClaugeWeb] \(s)") }
            #endif
        }
    }
}
