import SwiftUI

/// Faint "Clauge · v0.1.0" footer, bottom-right, used on Devices and Home.
struct VersionFooter: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Clauge · v\(AppInfo.version)")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.45))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
