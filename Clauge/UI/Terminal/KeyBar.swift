import SwiftUI

/// Horizontal bar of special keys the touch keyboard can't send. Order
/// matches Android: Esc, Tab, ↑, ↓, ←, →, Ctrl (a latch toggle).
struct KeyBar: View {
    @ObservedObject var vm: TerminalViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("esc") { vm.sendKey(KeyBytes.esc) }
                chip("tab") { vm.sendKey(KeyBytes.tab) }
                chip("↑") { vm.sendKey(KeyBytes.up) }
                chip("↓") { vm.sendKey(KeyBytes.down) }
                chip("←") { vm.sendKey(KeyBytes.left) }
                chip("→") { vm.sendKey(KeyBytes.right) }
                ctrlChip
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var ctrlChip: some View {
        Button { vm.toggleCtrl() } label: {
            Text("ctrl")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(vm.ctrlLatched ? Theme.background : Theme.textPrimary)
                .frame(minWidth: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(vm.ctrlLatched ? Theme.pink : Theme.surfaceHigh,
                           in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
