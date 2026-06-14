import Foundation

/// Human "x ago" string from an ISO-8601 timestamp, matching the Android
/// client's buckets: just now / Nm / Nh / Nd / Nw ago.
enum RelativeTime {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func format(_ isoString: String?) -> String? {
        guard let isoString, !isoString.isEmpty else { return nil }
        let date = isoFractional.date(from: isoString) ?? iso.date(from: isoString)
        guard let date else { return nil }
        let secs = max(0, Date().timeIntervalSince(date))
        switch secs {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(secs / 60))m ago"
        case ..<86400: return "\(Int(secs / 3600))h ago"
        case ..<604800: return "\(Int(secs / 86400))d ago"
        default: return "\(Int(secs / 604800))w ago"
        }
    }
}
