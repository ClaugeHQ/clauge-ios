import Foundation

/// REST client for the Clauge desktop companion server. Talks plain HTTP to
/// the active device, choosing whichever of its known hosts answers
/// `/healthz` first (so it follows the desktop across Wi-Fi / Tailscale).
final class CompanionClient {
    private let store: ServerStore
    /// Invoked on a 401 from an authed request (token no longer valid).
    var onUnauthorized: (@MainActor () -> Void)?

    private let defaultSession: URLSession
    private let probeSession: URLSession
    private let pairSession: URLSession

    private struct HostCache { let host: String; let at: Date }
    private var hostCache: [String: HostCache] = [:]
    private let hostCacheTTL: TimeInterval = 15

    init(store: ServerStore) {
        self.store = store
        defaultSession = URLSession(configuration: Self.config(timeout: 30))
        probeSession = URLSession(configuration: Self.config(timeout: 3))
        pairSession = URLSession(configuration: Self.config(timeout: 70))
    }

    private static func config(timeout: TimeInterval) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.waitsForConnectivity = false
        return c
    }

    // MARK: - URL helpers

    private func url(host: String, port: Int, path: String) -> URL {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = port
        c.path = path
        return c.url!
    }

    private func probe(host: String, port: Int) async -> Bool {
        var req = URLRequest(url: url(host: host, port: port, path: "/healthz"))
        req.timeoutInterval = 3
        guard let (_, resp) = try? await probeSession.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// First host that answers `/healthz`, cached for 15s. Falls back to the
    /// first known host so a request still produces a real network error
    /// (surfaced as `.deviceOffline`) when nothing is reachable.
    private func reachableHost(_ device: Device) async -> String {
        if let cached = hostCache[device.id], Date().timeIntervalSince(cached.at) < hostCacheTTL {
            return cached.host
        }
        let hosts = device.hosts
        let winner: String? = await withTaskGroup(of: String?.self) { group in
            for h in hosts {
                group.addTask { await self.probe(host: h, port: device.port) ? h : nil }
            }
            for await result in group where result != nil {
                group.cancelAll()
                return result
            }
            return nil
        }
        let host = winner ?? hosts.first ?? ""
        if winner != nil { hostCache[device.id] = HostCache(host: host, at: Date()) }
        return host
    }

    // MARK: - Request core

    private func authedRequest(_ path: String, method: String) async throws -> URLRequest {
        try await authedRequest(path, method: method, query: [])
    }

    private func authedRequest(_ path: String, method: String, query: [URLQueryItem]) async throws -> URLRequest {
        guard let device = await store.activeDevice else { throw NetError.notPaired }
        guard let token = await store.activeToken else { throw NetError.notPaired }
        let host = await reachableHost(device)
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = device.port
        c.path = path
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func run(_ req: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await defaultSession.data(for: req)
        } catch {
            throw NetError.deviceOffline
        }
        try check(resp, data: data)
        return data
    }

    private func check(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw NetError.badResponse }
        if http.statusCode == 401 {
            if let cb = onUnauthorized { Task { @MainActor in cb() } }
            throw NetError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetError.server(Self.extractError(data) ?? "HTTP \(http.statusCode)")
        }
    }

    private static func extractError(_ data: Data) -> String? {
        if let body = try? JSONDecoder().decode(ApiErrorBody.self, from: data), let e = body.error {
            return e
        }
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return String(s.prefix(200))
        }
        return nil
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw NetError.badResponse }
    }

    // MARK: - Endpoints

    /// Probe the QR's hosts in order, then POST `/pair` to the first
    /// reachable one. The desktop blocks up to ~60s waiting for approval.
    func pair(hosts: [String], port: Int, code: String, deviceName: String) async throws -> PairResponse {
        var pairingHost: String?
        for h in hosts where await probe(host: h, port: port) { pairingHost = h; break }
        guard let host = pairingHost else {
            throw NetError.server("Could not reach the desktop on any address. Make sure both devices are on the same network and the mobile server is on.")
        }
        var req = URLRequest(url: url(host: host, port: port, path: "/pair"))
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(PairRequest(code: code, deviceName: deviceName, platform: "ios"))
        let data: Data, resp: URLResponse
        do { (data, resp) = try await pairSession.data(for: req) }
        catch { throw NetError.deviceOffline }
        try check(resp, data: data)
        return try decode(data)
    }

    func healthz() async -> Bool {
        if await store.demoMode { return true }
        guard let device = await store.activeDevice else { return false }
        for h in device.hosts where await probe(host: h, port: device.port) { return true }
        return false
    }

    /// True if any of a device's hosts answers `/healthz`. Used by the
    /// device list to show online/offline.
    func reachable(_ device: Device) async -> Bool {
        if await store.demoMode { return true }
        for h in device.hosts where await probe(host: h, port: device.port) { return true }
        return false
    }

    func listAgentSessions() async throws -> [AgentSessionDto] {
        if await store.demoMode { return Demo.agentSessions }
        return try decode(try await run(authedRequest("/v1/sessions/agent", method: "GET")))
    }

    func listSshProfiles() async throws -> [SshProfileDto] {
        if await store.demoMode { return Demo.sshProfiles }
        return try decode(try await run(authedRequest("/v1/sessions/ssh", method: "GET")))
    }

    func spawnAgent(sessionId: String, requestId: String? = nil) async throws -> String {
        if await store.demoMode { return Demo.terminalId }
        var req = try await authedRequest("/v1/sessions/agent", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SpawnAgentRequest(sessionId: sessionId, newSession: nil, requestId: requestId))
        let out: SpawnResponse = try decode(try await run(req))
        return out.terminalId
    }

    func spawnSsh(profileId: String, requestId: String? = nil) async throws -> String {
        if await store.demoMode { return Demo.terminalId }
        var req = try await authedRequest("/v1/sessions/ssh", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SpawnSshRequest(profileId: profileId, requestId: requestId))
        let out: SpawnResponse = try decode(try await run(req))
        return out.terminalId
    }

    func spawnShell(cwd: String? = nil) async throws -> String {
        if await store.demoMode { return Demo.terminalId }
        var req = try await authedRequest("/v1/sessions/shell", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let cwd = cwd, !cwd.isEmpty {
            req.httpBody = try JSONSerialization.data(withJSONObject: ["cwd": cwd])
        } else {
            req.httpBody = Data("{}".utf8)
        }
        let out: SpawnResponse = try decode(try await run(req))
        return out.terminalId
    }

    /// Abort an in-flight spawn the desktop hasn't finished opening.
    func cancelOpen(requestId: String) async throws {
        if await store.demoMode { return }
        var req = try await authedRequest("/v1/sessions/cancel", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(CancelOpenRequest(requestId: requestId))
        _ = try await run(req)
    }

    // MARK: - System metrics

    func sysMetrics() async throws -> SysMetricsDto {
        if await store.demoMode { return Demo.sysMetrics }
        return try decode(try await run(authedRequest("/v1/sys/metrics", method: "GET")))
    }

    // MARK: - Files

    func fsList(path: String?, hidden: Bool) async throws -> FsListDto {
        if await store.demoMode { return Demo.fsList(path) }
        var q = [URLQueryItem(name: "hidden", value: hidden ? "true" : "false")]
        if let p = path, !p.isEmpty { q.append(URLQueryItem(name: "path", value: p)) }
        return try decode(try await run(authedRequest("/v1/fs/list", method: "GET", query: q)))
    }

    func fsRead(path: String) async throws -> FsReadDto {
        if await store.demoMode { return Demo.fsRead(path) }
        return try decode(try await run(authedRequest("/v1/fs/read", method: "GET", query: [URLQueryItem(name: "path", value: path)])))
    }

    func fsSearch(path: String?, query: String) async throws -> FsSearchDto {
        if await store.demoMode { return Demo.fsSearch }
        var q = [URLQueryItem(name: "q", value: query)]
        if let p = path, !p.isEmpty { q.append(URLQueryItem(name: "path", value: p)) }
        return try decode(try await run(authedRequest("/v1/fs/search", method: "GET", query: q)))
    }

    func fsMkdir(path: String) async throws {
        if await store.demoMode { return }
        var req = try await authedRequest("/v1/fs/mkdir", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(FsPathBody(path: path))
        _ = try await run(req)
    }

    func fsWrite(path: String, content: String) async throws {
        if await store.demoMode { return }
        var req = try await authedRequest("/v1/fs/write", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(FsWriteBody(path: path, content: content))
        _ = try await run(req)
    }

    func fsDelete(path: String) async throws {
        if await store.demoMode { return }
        _ = try await run(authedRequest("/v1/fs/delete", method: "DELETE", query: [URLQueryItem(name: "path", value: path)]))
    }

    func fsDownload(path: String) async throws -> Data {
        if await store.demoMode { return Demo.downloadBytes }
        return try await run(authedRequest("/v1/fs/download", method: "GET", query: [URLQueryItem(name: "path", value: path)]))
    }

    func fsUpload(dir: String, name: String, data: Data) async throws {
        if await store.demoMode { return }
        var req = try await authedRequest("/v1/fs/upload", method: "POST",
                                         query: [URLQueryItem(name: "path", value: dir),
                                                 URLQueryItem(name: "name", value: name)])
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try await run(req)
    }

    // MARK: - Ports + reverse proxy

    func ports() async throws -> PortsDto {
        if await store.demoMode { return Demo.ports }
        return try decode(try await run(authedRequest("/v1/ports", method: "GET")))
    }

    /// Base URL of the desktop's reverse proxy to a localhost dev port.
    func proxyBase(port: Int) async -> URL? {
        if await store.demoMode { return Demo.proxyBase(port: port) }
        guard let device = await store.activeDevice else { return nil }
        let host = await reachableHost(device)
        if host.isEmpty { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = device.port
        c.path = "/v1/proxy/\(port)/"
        return c.url
    }

    /// Bearer token the in-app browser attaches to proxied requests only.
    func authToken() async -> String? { await store.activeToken }

    func endTerminal(_ terminalId: String) async throws {
        if await store.demoMode { return }
        _ = try await run(authedRequest("/v1/term/\(terminalId)", method: "DELETE"))
    }

    func recentProjects() async throws -> [String] {
        if await store.demoMode { return Demo.recentProjects }
        return try decode(try await run(authedRequest("/v1/projects/recent", method: "GET")))
    }

    func serverInfo() async throws -> ServerInfoDto {
        if await store.demoMode { return Demo.serverInfo }
        return try decode(try await run(authedRequest("/v1/server/info", method: "GET")))
    }

    func registerFcm(token: String) async throws {
        if await store.demoMode { return }
        var req = try await authedRequest("/v1/device/fcm", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(FcmTokenRequest(token: token))
        _ = try await run(req)
    }

    /// The base URL the terminal WebSocket should derive from (active device,
    /// first reachable host). Returns nil when not paired.
    func webSocketBase() async -> (host: String, port: Int, token: String)? {
        guard let device = await store.activeDevice, let token = await store.activeToken else { return nil }
        let host = await reachableHost(device)
        return (host, device.port, token)
    }
}

// MARK: - Demo (offline review)

/// Canned responses served when `store.demoMode` is on, so every screen is
/// populated without a desktop or any network. All values are static; the
/// only computed one is each agent session's `lastUsedAt` (set to "now" so the
/// list reads as recent).
private enum Demo {
    static let terminalId = "demo-term-1"

    static let recentProjects = ["/Users/demo/projects/web", "/Users/demo/projects/api"]

    static let readme = """
    # Demo Project

    This is sample content shown in Clauge demo mode.

    - Browse files
    - Open a terminal
    - View system metrics

    """

    static let notes = "Sample notes shown in Clauge demo mode.\n"

    static var downloadBytes: Data { Data(readme.utf8) }

    static func make<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static let agentSessions: [AgentSessionDto] = {
        let now = ISO8601DateFormatter().string(from: Date())
        return make("""
        [
          {"id":"demo-agent-1","title":"feature/auth-refactor","provider":"claude","status":"running","projectPath":"/Users/demo/projects/web","purpose":"feature","awaitingInput":false,"lastUsedAt":"\(now)"},
          {"id":"demo-agent-2","title":"bugfix/payment-retry","provider":"codex","status":"idle","projectPath":"/Users/demo/projects/api","purpose":"bugfix","awaitingInput":false,"lastUsedAt":"\(now)"}
        ]
        """)
    }()

    static let sshProfiles: [SshProfileDto] = make("""
    [
      {"id":"demo-ssh-1","name":"prod-web","host":"10.0.0.12","username":"deploy","port":22,"connected":false,"live":false,"liveTerminals":[]},
      {"id":"demo-ssh-2","name":"raspberry-pi","host":"pi.local","username":"pi","port":22,"connected":false,"live":false,"liveTerminals":[]}
    ]
    """)

    static let sysMetrics: SysMetricsDto = make("""
    {
      "serverName":"Demo Desktop","platform":"macos","uptimeSecs":184523,
      "cpu":{"usagePct":23.5,"brand":"Apple M3","cores":8},
      "memory":{"totalBytes":17179869184,"usedBytes":9512345600,"availableBytes":7667523584},
      "battery":{"percent":82,"charging":true},
      "volumes":[{"name":"Macintosh HD","mountPoint":"/","totalBytes":994662584320,"usedBytes":612000000000,"availableBytes":382662584320}]
    }
    """)

    static let ports: PortsDto = make("""
    {"ports":[
      {"port":3000,"bindAddr":"127.0.0.1","pid":4821,"process":"node"},
      {"port":5432,"bindAddr":"127.0.0.1","pid":991,"process":"postgres"}
    ]}
    """)

    static let fsSearch: FsSearchDto = make("{\"entries\":[]}")

    /// Current-folder file tree rooted at `/Users/demo`.
    static func fsList(_ path: String?) -> FsListDto {
        switch path {
        case .none, .some("/Users/demo"):
            return make("""
            {"path":"/Users/demo","parent":null,"entries":[
              {"name":"projects","path":"/Users/demo/projects","isDir":true,"size":0},
              {"name":"Documents","path":"/Users/demo/Documents","isDir":true,"size":0},
              {"name":"README.md","path":"/Users/demo/README.md","isDir":false,"size":1240},
              {"name":"notes.txt","path":"/Users/demo/notes.txt","isDir":false,"size":420}
            ]}
            """)
        case .some("/Users/demo/projects"):
            return make("""
            {"path":"/Users/demo/projects","parent":"/Users/demo","entries":[
              {"name":"web","path":"/Users/demo/projects/web","isDir":true,"size":0},
              {"name":"api","path":"/Users/demo/projects/api","isDir":true,"size":0}
            ]}
            """)
        case .some(let p):
            let parent = (p as NSString).deletingLastPathComponent
            let obj: [String: Any] = ["path": p, "parent": parent.isEmpty ? "/Users/demo" : parent, "entries": []]
            let data = try! JSONSerialization.data(withJSONObject: obj)
            return try! JSONDecoder().decode(FsListDto.self, from: data)
        }
    }

    static func fsRead(_ path: String) -> FsReadDto {
        let text = path.hasSuffix("notes.txt") ? notes
            : (path.hasSuffix(".md") || path.hasSuffix("README.md") ? readme : "Sample file content shown in Clauge demo mode.\n")
        let obj: [String: Any] = ["path": path, "binary": false, "tooLarge": false,
                                  "content": text, "size": text.utf8.count]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(FsReadDto.self, from: data)
    }

    /// A self-contained page (no network) for the in-app browser when a demo
    /// port is opened.
    static func proxyBase(port: Int) -> URL? {
        let html = """
        <html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='font-family:-apple-system,sans-serif;background:#060414;color:#e8e8ee;margin:0;padding:28px'>
        <h2 style='color:#ff5fa2'>Demo dev server</h2>
        <p>This page is served locally in Clauge demo mode — no network is used.</p>
        <p>Pretend this is your app running on <code>localhost:\(port)</code>.</p>
        </body></html>
        """
        let encoded = html.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "data:text/html,\(encoded)")
    }

    static let serverInfo: ServerInfoDto = make("{\"serverName\":\"Demo Desktop\",\"version\":\"demo\"}")
}
