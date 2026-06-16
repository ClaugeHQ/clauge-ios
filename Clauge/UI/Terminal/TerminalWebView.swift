import SwiftUI
import WebKit

/// Bridges the bundled `term.html` (xterm.js) to native. JS calls
/// `window.AndroidTerm.*` (shimmed below to WebKit message handlers); native
/// drives the terminal via `window.*` functions evaluated on the web view.
@MainActor
final class TerminalBridge: NSObject, ObservableObject {
    weak var webView: WKWebView?

    // JS → native
    var onReady: ((Int, Int) -> Void)?
    var onData: ((String) -> Void)?      // base64
    var onResize: ((Int, Int) -> Void)?
    var onCtrlLatchConsumed: (() -> Void)?

    private var pageLoaded = false
    private var pending: [String] = []

    // native → JS
    func write(_ b64: String) { eval("window.write('\(b64)')") }
    func writeRaw(_ b64: String) { eval("window.writeRaw('\(b64)')") }
    func resizeTerm(_ cols: Int, _ rows: Int) { eval("window.resizeTerm(\(cols),\(rows))") }
    func refit() { eval("window.refit()") }
    func setExited() { eval("window.setExited()") }
    func setModifier(_ js: String?) { eval("window.setModifier(\(js.map { "'\($0)'" } ?? "null"))") }
    func sendKey(_ b64: String) { eval("window.sendKey('\(b64)')") }
    func focusTerm() { eval("window.focusTerm()") }
    func clearTerm() { eval("window.clearTerm()") }

    private func eval(_ js: String) {
        if pageLoaded, let webView {
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            pending.append(js)
        }
    }

    fileprivate func pageDidLoad() {
        pageLoaded = true
        guard let webView else { return }
        for js in pending { webView.evaluateJavaScript(js, completionHandler: nil) }
        pending.removeAll()
    }
}

extension TerminalBridge: WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        switch message.name {
        case "onData":
            if let b64 = message.body as? String { onData?(b64) }
        case "onResize":
            if let d = message.body as? [String: Any],
               let c = d["cols"] as? Int, let r = d["rows"] as? Int { onResize?(c, r) }
        case "onReady":
            if let d = message.body as? [String: Any],
               let c = d["cols"] as? Int, let r = d["rows"] as? Int { onReady?(c, r) }
        case "onCtrlLatchConsumed":
            onCtrlLatchConsumed?()
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageDidLoad()
    }
}

/// Weak forwarder so the user content controller doesn't retain the bridge.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: TerminalBridge?
    init(_ target: TerminalBridge) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

struct TerminalWebView: UIViewRepresentable {
    let bridge: TerminalBridge

    private static let shim = """
    window.AndroidTerm = {
      onData: function(b64){ window.webkit.messageHandlers.onData.postMessage(b64); },
      onResize: function(c,r){ window.webkit.messageHandlers.onResize.postMessage({cols:c,rows:r}); },
      onReady: function(c,r){ window.webkit.messageHandlers.onReady.postMessage({cols:c,rows:r}); },
      onCtrlLatchConsumed: function(){ window.webkit.messageHandlers.onCtrlLatchConsumed.postMessage(''); },
      onJsError: function(m){ },
      log: function(m){ }
    };
    """

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let weak = WeakHandler(bridge)
        for name in ["onData", "onResize", "onReady", "onCtrlLatchConsumed"] {
            controller.add(weak, name: name)
        }
        controller.addUserScript(WKUserScript(source: Self.shim,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = bridge
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0x06/255, green: 0x04/255, blue: 0x14/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        bridge.webView = webView

        if let url = Bundle.main.url(forResource: "term", withExtension: "html", subdirectory: "term") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
