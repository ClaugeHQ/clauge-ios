import Foundation

/// Whether tapping a session row attaches to an already-live terminal or
/// must spawn a fresh one on the desktop.
enum AttachDecision: Equatable {
    case live(String) // existing terminalId
    case spawn

    static func forAgent(_ s: AgentSessionDto) -> AttachDecision {
        if let t = s.liveTerminalId, !t.isEmpty { return .live(t) }
        return .spawn
    }

    static func forSsh(_ p: SshProfileDto) -> AttachDecision {
        if let t = p.liveTerminals.first(where: { !$0.terminalId.isEmpty })?.terminalId {
            return .live(t)
        }
        return .spawn
    }
}
