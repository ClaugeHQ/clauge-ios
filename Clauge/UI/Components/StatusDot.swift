import SwiftUI

/// Small status circle. When `pulsing` (an agent awaiting input) it fades in
/// and out to draw the eye, matching the Android amber pulse.
struct StatusDot: View {
    let color: Color
    var pulsing: Bool = false
    var diameter: CGFloat = 10

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .opacity(pulsing ? (animating ? 0.35 : 1.0) : 1.0)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
    }
}
