import Foundation

/// Exponential backoff for WebSocket reconnects: 1, 2, 4, 8, 16, 30, 30s…
/// (base 1s, doubling, capped at 30s). Reset after a successful open.
struct BackoffPolicy {
    let baseMs: Int = 1000
    let capMs: Int = 30000
    private var attempt = 0

    mutating func nextDelay() -> Duration {
        let shift = min(attempt, 30)
        let raw = baseMs << shift // may overflow for large shift; capped below
        let ms = (shift >= 20 || raw > capMs || raw <= 0) ? capMs : raw
        attempt += 1
        return .milliseconds(ms)
    }

    mutating func reset() {
        attempt = 0
    }
}
