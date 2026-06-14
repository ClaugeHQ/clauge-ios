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
        guard let device = await store.activeDevice else { throw NetError.notPaired }
        guard let token = await store.activeToken else { throw NetError.notPaired }
        let host = await reachableHost(device)
        var req = URLRequest(url: url(host: host, port: device.port, path: path))
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
        guard let device = await store.activeDevice else { return false }
        for h in device.hosts where await probe(host: h, port: device.port) { return true }
        return false
    }

    /// True if any of a device's hosts answers `/healthz`. Used by the
    /// device list to show online/offline.
    func reachable(_ device: Device) async -> Bool {
        for h in device.hosts where await probe(host: h, port: device.port) { return true }
        return false
    }

    func listAgentSessions() async throws -> [AgentSessionDto] {
        try decode(try await run(authedRequest("/v1/sessions/agent", method: "GET")))
    }

    func listSshProfiles() async throws -> [SshProfileDto] {
        try decode(try await run(authedRequest("/v1/sessions/ssh", method: "GET")))
    }

    func spawnAgent(sessionId: String) async throws -> String {
        var req = try await authedRequest("/v1/sessions/agent", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SpawnAgentRequest(sessionId: sessionId, newSession: nil))
        let out: SpawnResponse = try decode(try await run(req))
        return out.terminalId
    }

    func spawnSsh(profileId: String) async throws -> String {
        var req = try await authedRequest("/v1/sessions/ssh", method: "POST")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SpawnSshRequest(profileId: profileId))
        let out: SpawnResponse = try decode(try await run(req))
        return out.terminalId
    }

    func endTerminal(_ terminalId: String) async throws {
        _ = try await run(authedRequest("/v1/term/\(terminalId)", method: "DELETE"))
    }

    func recentProjects() async throws -> [String] {
        try decode(try await run(authedRequest("/v1/projects/recent", method: "GET")))
    }

    func serverInfo() async throws -> ServerInfoDto {
        try decode(try await run(authedRequest("/v1/server/info", method: "GET")))
    }

    func registerFcm(token: String) async throws {
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
