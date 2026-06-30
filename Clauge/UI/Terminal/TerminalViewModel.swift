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

    /// Offline review demo: no socket — the transcript is written to the bridge
    /// and typed keys are echoed locally.
    private let isDemo: Bool
    private var demoStarted = false

    init(terminalId: String) {
        self.terminalId = terminalId
        self.isDemo = Services.shared.store.demoMode
        bridge.onReady = { [weak self] cols, rows in self?.openSocket(cols: cols, rows: rows) }
        bridge.onData = { [weak self] b64 in
            guard let self else { return }
            if self.isDemo { self.demoEcho(b64) } else { self.socket?.sendInput(base64: b64) }
        }
        bridge.onResize = { [weak self] cols, rows in self?.socket?.sendResize(cols: cols, rows: rows) }
        bridge.onCtrlLatchConsumed = { [weak self] in self?.armedModifier = nil }
    }

    /// The WebView reported its fit size — open the mirror socket with it.
    private func openSocket(cols: Int, rows: Int) {
        guard socket == nil else { return }
        if isDemo { startDemo(); return }
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

    // MARK: Demo session

    /// Play a scripted transcript once the WebView is ready, then leave a live
    /// prompt that echoes typed keys — no shell, no socket.
    private func startDemo() {
        guard !demoStarted else { return }
        demoStarted = true
        connected = true
        bridge.write(b64(DemoTerminal.transcript))
    }

    /// Echo locally so the session feels live: newline reprints the prompt,
    /// backspace erases, everything else is written verbatim.
    private func demoEcho(_ input: String) {
        guard let data = Data(base64Encoded: input) else { return }
        let newline = Array("\r\n\(DemoTerminal.prompt)".utf8)
        let bytes = Array(data)
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            switch byte {
            case 0x0d, 0x0a:
                // Coalesce a CRLF pair (or a lone CR/LF) into one newline + prompt.
                out.append(contentsOf: newline)
                if byte == 0x0d, i + 1 < bytes.count, bytes[i + 1] == 0x0a { i += 1 }
            case 0x7f, 0x08: out.append(contentsOf: [0x08, 0x20, 0x08])
            default: out.append(byte)
            }
            i += 1
        }
        bridge.write(Data(out).base64EncodedString())
    }

    private func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }

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

/// Scripted content for the offline review demo terminal.
private enum DemoTerminal {
    static let prompt = "demo@Demo-Desktop ~/projects/web $ "

    static let transcript: String = {
        let lines = [
            "\(prompt)npm run dev",
            "",
            "> web@1.0.0 dev",
            "> vite",
            "",
            "  VITE v5.2.0  ready in 412 ms",
            "",
            "  \u{279C}  Local:   http://localhost:3000/",
            "  \u{279C}  press h + enter to show help",
            "",
            prompt,
        ]
        return lines.joined(separator: "\r\n")
    }()
}
