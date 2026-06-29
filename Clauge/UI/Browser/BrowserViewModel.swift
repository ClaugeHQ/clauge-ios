import Foundation
import SwiftUI

enum BrowserViewState: Equatable {
    case home
    case ports
    case web(url: String, isProxy: Bool)
}

struct RecentEntry: Identifiable, Equatable {
    let url: String
    let title: String
    let at: Date
    var id: String { url }
}

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var view: BrowserViewState = .home
    @Published var ports: [PortInfoDto] = []
    @Published var portsLoading = false
    @Published var portsError: String?
    @Published var portQuery = ""
    @Published var processFilter: String?
    @Published var recents: [RecentEntry] = []
    @Published var title = "Home"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var consoleOpen = false

    private let client = Services.shared.client
    private var refreshTask: Task<Void, Never>?

    func onAppear() {
        if ports.isEmpty { refreshPorts() }
    }

    func refreshPorts() {
        if refreshTask != nil { return }
        if ports.isEmpty { portsLoading = true }
        refreshTask = Task { [weak self] in
            await self?.loadPorts()
            self?.refreshTask = nil
        }
    }

    private func loadPorts() async {
        do {
            let res = try await client.ports()
            ports = res.ports
            portsLoading = false
            portsError = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            portsLoading = false
            portsError = error.localizedDescription
        }
    }

    func goHome() {
        view = .home
        title = "Home"
        consoleOpen = false
        canGoBack = false
        canGoForward = false
    }

    func goPorts() {
        view = .ports
        title = "Ports"
        consoleOpen = false
        canGoBack = false
        canGoForward = false
    }

    /// Address-bar input: a bare port/localhost:port opens via the proxy, anything else loads as a URL.
    func submit(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if let local = Self.parseLocalhost(t) {
            openPort(local.port, suffix: local.suffix)
        } else {
            openWeb(Self.normalizeUrl(t))
        }
    }

    func openPort(_ port: Int, suffix: String = "") {
        Task { [weak self] in
            guard let self else { return }
            if let base = await self.client.proxyBase(port: port) {
                // proxyBase ends in `/`; append the localhost path/query through
                // the proxy rather than loading it directly on the phone.
                var full = base.absoluteString
                if suffix.hasPrefix("/") {
                    full += String(suffix.dropFirst())
                } else {
                    full += suffix
                }
                let label = "localhost:\(port)\(suffix)"
                self.view = .web(url: full, isProxy: true)
                self.title = label
                self.consoleOpen = false
                self.canGoBack = false
                self.canGoForward = false
                self.addRecent(url: label, title: label)
            } else {
                self.portsError = "Desktop unreachable"
            }
        }
    }

    func openWeb(_ url: String) {
        view = .web(url: url, isProxy: false)
        title = url
        consoleOpen = false
        canGoBack = false
        canGoForward = false
        addRecent(url: url, title: url)
    }

    func setNav(back: Bool, forward: Bool) {
        canGoBack = back
        canGoForward = forward
    }

    func setPageTitle(_ t: String) {
        if !t.isEmpty { title = t }
    }

    func toggleConsole() {
        consoleOpen.toggle()
    }

    func addRecent(url: String, title: String) {
        let rest = recents.filter { $0.url != url }
        let entry = RecentEntry(url: url, title: title.isEmpty ? url : title, at: Date())
        recents = Array(([entry] + rest).prefix(20))
    }

    /// Recents are session-only — dropped when the user leaves the Browser
    /// (and naturally on app close, since nothing is persisted).
    func clearRecents() {
        recents = []
    }

    func authToken() async -> String? {
        await client.authToken()
    }

    /// A localhost target — port plus any trailing path/query to forward through
    /// the proxy (e.g. `localhost:3000/foo?x=1`).
    struct LocalTarget: Equatable {
        let port: Int
        let suffix: String
    }

    /// Detects a localhost dev URL (bare port, `localhost:port`, `127.0.0.1:port`,
    /// with or without an `http(s)://` scheme and a `/path?query`). The host is
    /// pinned to localhost/127.0.0.1 so real hostnames fall through to `openWeb`.
    static func parseLocalhost(_ input: String) -> LocalTarget? {
        let t = input.trimmingCharacters(in: .whitespaces)
        let pattern = "^(?:https?://)?(?:localhost|127\\.0\\.0\\.1)?:?(\\d{2,5})((?:/|\\?)[^\\s]*)?$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        guard let m = re.firstMatch(in: t, range: range), m.range == range else { return nil }
        guard let g = Range(m.range(at: 1), in: t), let port = Int(t[g]) else { return nil }
        guard (1...65535).contains(port) else { return nil }
        var suffix = ""
        if m.range(at: 2).location != NSNotFound, let s = Range(m.range(at: 2), in: t) {
            suffix = String(t[s])
        }
        return LocalTarget(port: port, suffix: suffix)
    }

    static func normalizeUrl(_ input: String) -> String {
        let t = input.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "https://\(t)"
    }
}
