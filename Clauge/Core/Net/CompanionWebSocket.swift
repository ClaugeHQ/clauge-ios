import Foundation

/// Terminal mirror over WebSocket. Connects to
/// `ws://host:port/v1/term/{id}/ws?cols=&rows=` with the phone's fit size,
/// authenticates with the bearer token on the upgrade request, and relays
/// the desktop's `replay/out/size/exit` frames. Reconnects with backoff.
/// Callbacks fire on the main actor in receive order.
final class CompanionWebSocket {
    private let client: CompanionClient
    private let terminalId: String

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var backoff = BackoffPolicy()
    private var loop: Task<Void, Never>?

    private var connectCols = 80
    private var connectRows = 24
    private var closedByUser = false
    private var ended = false

    // Callbacks (invoked @MainActor).
    var onReplay: ((String) -> Void)?     // base64 bytes
    var onOut: ((String) -> Void)?        // base64 bytes
    var onSize: ((Int, Int) -> Void)?
    var onExit: (() -> Void)?
    var onConnected: ((Bool) -> Void)?

    init(client: CompanionClient, terminalId: String) {
        self.client = client
        self.terminalId = terminalId
    }

    func connect(cols: Int, rows: Int) {
        connectCols = max(1, cols)
        connectRows = max(1, rows)
        guard loop == nil else { return }
        loop = Task { await runLoop() }
    }

    func sendInput(base64 b64: String) { sendJSON(["t": "in", "d": b64]) }

    func sendResize(cols: Int, rows: Int) { sendJSON(["t": "resize", "cols": cols, "rows": rows]) }

    func sendPing() { sendJSON(["t": "ping"]) }

    /// Detach without killing the desktop session.
    func close() {
        closedByUser = true
        loop?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    // MARK: - Loop

    private func runLoop() async {
        while !closedByUser && !ended && !Task.isCancelled {
            guard let base = await client.webSocketBase() else {
                try? await Task.sleep(for: backoff.nextDelay())
                continue
            }
            var comps = URLComponents()
            comps.scheme = "ws"
            comps.host = base.host
            comps.port = base.port
            comps.path = "/v1/term/\(terminalId)/ws"
            comps.queryItems = [
                URLQueryItem(name: "cols", value: "\(connectCols)"),
                URLQueryItem(name: "rows", value: "\(connectRows)"),
            ]
            guard let url = comps.url else { break }

            var req = URLRequest(url: url)
            req.setValue("Bearer \(base.token)", forHTTPHeaderField: "Authorization")
            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: req)
            self.session = session
            self.task = task
            task.resume()

            var gotFirst = false
            do {
                while !closedByUser && !ended {
                    let message = try await task.receive()
                    if !gotFirst { gotFirst = true; backoff.reset(); await setConnected(true) }
                    await handle(message)
                }
            } catch {
                // dropped — fall through to reconnect
            }
            await setConnected(false)
            task.cancel(with: .goingAway, reason: nil)
            self.task = nil
            if closedByUser || ended || Task.isCancelled { break }
            try? await Task.sleep(for: backoff.nextDelay())
        }
    }

    @MainActor private func setConnected(_ v: Bool) { onConnected?(v) }

    @MainActor
    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["t"] as? String else { return }
        switch t {
        case "replay":
            if let d = obj["d"] as? String { onReplay?(d) }
        case "out":
            if let d = obj["d"] as? String { onOut?(d) }
        case "size":
            if let cols = obj["cols"] as? Int, let rows = obj["rows"] as? Int { onSize?(cols, rows) }
        case "exit":
            ended = true
            onExit?()
        default:
            break
        }
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }
}
