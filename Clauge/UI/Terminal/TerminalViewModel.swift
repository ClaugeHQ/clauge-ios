import Foundation
import SwiftUI
import UIKit

/// Key-bar modifier. `js` is the value passed to term.html's window.setModifier.
enum TermModifier: String, CaseIterable {
    case ctrl, alt
    var label: String { rawValue }
    var js: String { rawValue }
}

@MainActor
final class TerminalViewModel: ObservableObject {
    let terminalId: String
    let bridge = TerminalBridge()

    /// Which modifier the chip represents, and whether it's armed for the next key.
    @Published var modifierSlot: TermModifier = .ctrl
    @Published var armedModifier: TermModifier?
    @Published var exited = false
    @Published var connected = false

    private let client = Services.shared.client
    private var socket: CompanionWebSocket?

    init(terminalId: String) {
        self.terminalId = terminalId
        bridge.onReady = { [weak self] cols, rows in self?.openSocket(cols: cols, rows: rows) }
        bridge.onData = { [weak self] b64 in self?.socket?.sendInput(base64: b64) }
        bridge.onResize = { [weak self] cols, rows in self?.socket?.sendResize(cols: cols, rows: rows) }
        bridge.onCtrlLatchConsumed = { [weak self] in self?.armedModifier = nil }
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

    /// Tap the modifier chip: arm the current slot, or disarm if already armed.
    func toggleModifier() {
        armedModifier = (armedModifier == modifierSlot) ? nil : modifierSlot
        bridge.setModifier(armedModifier?.js)
    }

    /// Pick a modifier from the long-press menu: switch the slot and arm it.
    func pickModifier(_ m: TermModifier) {
        modifierSlot = m
        armedModifier = m
        bridge.setModifier(m.js)
    }

    /// Key-bar keys go through sendKey so the armed modifier applies (Ctrl+C etc.).
    func sendKey(_ bytes: [UInt8]) {
        bridge.sendKey(KeyBytes.base64(bytes))
    }

    /// Paste the clipboard into the PTY verbatim. Clear any armed modifier first
    /// — a raw paste bypasses modifier consumption, so it would otherwise bleed
    /// into the next key.
    func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        if armedModifier != nil {
            armedModifier = nil
            bridge.setModifier(nil)
        }
        bridge.writeRaw(KeyBytes.base64(Array(text.utf8)))
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
