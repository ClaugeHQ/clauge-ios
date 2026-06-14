import SwiftUI

/// Clauge dark palette — hex values mirror the Android theme exactly.
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 6 { s += "FF" }
        var rgba: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgba)
        self.init(
            .sRGB,
            red: Double((rgba >> 24) & 0xFF) / 255,
            green: Double((rgba >> 16) & 0xFF) / 255,
            blue: Double((rgba >> 8) & 0xFF) / 255,
            opacity: Double(rgba & 0xFF) / 255
        )
    }
}

enum Theme {
    // Surfaces
    static let background = Color(hex: "#060414")
    static let surface = Color(hex: "#100D1F")
    static let surfaceHigh = Color(hex: "#1A1530")
    static let surfaceHighest = Color(hex: "#241D40")

    // Brand
    static let pink = Color(hex: "#F472B6")
    static let pinkDim = Color(hex: "#D8559B")
    static let pinkContainer = Color(hex: "#4A1B36")
    static let onPinkContainer = Color(hex: "#FFD9E8")
    static let violet = Color(hex: "#A78BFA")
    static let violetContainer = Color(hex: "#2E2354")
    static let onVioletContainer = Color(hex: "#E5DCFF")

    // Text
    static let textPrimary = Color(hex: "#EDE9F6")
    static let textSecondary = Color(hex: "#9D97B5")

    // Lines
    static let outline = Color(hex: "#45405C")
    static let outlineVariant = Color(hex: "#2A2540")

    // Error
    static let error = Color(hex: "#F87171")
    static let onError = Color(hex: "#3B0A0A")
    static let errorContainer = Color(hex: "#4C1424")
    static let onErrorContainer = Color(hex: "#FFDADD")

    // Status
    static let statusRunning = Color(hex: "#4ADE80")
    static let statusIdle = Color(hex: "#9CA3AF")
    static let statusExited = Color(hex: "#F87171")
    static let statusAwaiting = Color(hex: "#FBBF24")

    // Device dots
    static let deviceOnline = Color(hex: "#4ADE80")
    static let deviceOffline = Color(hex: "#F87171")
    static let deviceChecking = Color(hex: "#9CA3AF")

    /// Purpose pill base color (rendered at ~13% opacity behind the label).
    static func purposeColor(_ purpose: String?) -> Color {
        switch (purpose ?? "").lowercased() {
        case "brainstorming": return Color(hex: "#D2A8FF")
        case "development": return Color(hex: "#3FB950")
        case "code review": return Color(hex: "#58A6FF")
        case "pr review": return Color(hex: "#D29922")
        case "debugging": return Color(hex: "#F85149")
        default: return Color(hex: "#8B949E")
        }
    }

    static func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running": return statusRunning
        case "exited": return statusExited
        default: return statusIdle
        }
    }
}
