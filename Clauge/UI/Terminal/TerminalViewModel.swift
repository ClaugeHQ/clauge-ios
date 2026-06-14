import Foundation
import SwiftUI

@MainActor
final class TerminalViewModel: ObservableObject {
    let terminalId: String
    let bridge = TerminalBridge()

    @Published var ctrlLatched = false
    @Published var exited = false
    @Published var connected = false

    private let client = Services.shared.client
    private var socket: CompanionWebSocket?

    init(terminalId: String) {
        self.terminalId = terminalId
        bridge.onReady = { [weak self] cols, rows in self?.openSocket(cols: cols, rows: rows) }
        bridge.onData = { [weak self] b64 in self?.socket?.sendInput(base64: b64) }
        bridge.onResize = { [weak self] cols, rows in self?.socket?.sendResize(cols: cols, rows: rows) }
        bridge.onCtrlLatchConsumed = { [weak self] in self?.ctrlLatched = false }
    }

    /// The WebView reported its fit size — open the mirror socket with it.
    private func openSocket(cols: Int, rows: Int) {
        guard socket == nil else { return }
        let ws = CompanionWebSocket(client: client, terminalId: terminalId)
        ws.onReplay = { [weak self] b64 in self?.bridge.write(b64) }
        ws.onOut = { [weak self] b64 in self?.bridge.write(b64) }
        ws.onSize = { [weak self] c, r in self?.bridge.resizeTerm(c, r) }
        ws.onExit = { [weak self] in
            self?.exited = true
            self?.bridge.setExited()
        }
        ws.onConnected = { [weak self] v in self?.connected = v }
        socket = ws
        ws.connect(cols: cols, rows: rows)
    }

    // MARK: Key bar

    func toggleCtrl() {
        ctrlLatched.toggle()
        bridge.setCtrlLatch(ctrlLatched)
    }

    func sendKey(_ bytes: [UInt8]) {
        bridge.writeRaw(KeyBytes.base64(bytes))
    }

    func refit() { bridge.refit() }

    // MARK: Lifecycle

    /// Back (←): leave the session running, just close the mirror.
    func detach() { socket?.close() }

    /// End (×): kill the desktop terminal, then close.
    func end() async {
        try? await client.endTerminal(terminalId)
        socket?.close()
    }
}
