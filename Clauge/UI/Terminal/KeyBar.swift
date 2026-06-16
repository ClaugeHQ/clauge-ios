import SwiftUI
import UIKit

/// Special-key bar the touch keyboard can't send: esc, a switchable Ctrl/Alt
/// modifier (tap to arm, long-press to switch), tab, paste, and a drag joystick
/// for the arrow keys.
struct KeyBar: View {
    @ObservedObject var vm: TerminalViewModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                chip("esc") { vm.sendKey(KeyBytes.esc) }
                ModifierChip(vm: vm)
                chip("tab") { vm.sendKey(KeyBytes.tab) }
                chip("paste") { vm.paste() }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surfaceHigh, in: Capsule())

            Joystick(size: 48) { bytes in vm.sendKey(bytes) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// Tap = arm the current modifier; long-press = menu to switch Ctrl/Alt.
private struct ModifierChip: View {
    @ObservedObject var vm: TerminalViewModel

    var body: some View {
        let isArmed = vm.armedModifier == vm.modifierSlot
        Menu {
            ForEach(TermModifier.allCases, id: \.self) { m in
                Button(m.label) { vm.pickModifier(m) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(vm.modifierSlot.label)
                    .font(.system(.subheadline, design: .monospaced))
                Image(systemName: "chevron.up").font(.system(size: 9))
            }
            .foregroundStyle(isArmed ? Theme.background : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isArmed ? Theme.pink : Color.clear, in: Capsule())
        } primaryAction: {
            vm.toggleModifier()
        }
        .buttonStyle(.plain)
    }
}

/// Drag pad: the knob follows the finger and sends an arrow key on entry,
/// auto-repeating (160ms) with a haptic tick while held in a direction.
private struct Joystick: View {
    let size: CGFloat
    let onDirection: ([UInt8]) -> Void

    @State private var knob: CGSize = .zero
    @State private var currentDir: [UInt8]?
    @State private var repeatTask: Task<Void, Never>?

    private var radius: CGFloat { size / 2 }
    private var knobSize: CGFloat { size * 0.4 }
    private var deadZone: CGFloat { size * 0.45 }

    var body: some View {
        ZStack {
            Circle().fill(Theme.surfaceHigh)
            Circle().fill(Theme.textSecondary)
                .frame(width: knobSize, height: knobSize)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityElement()
        .accessibilityLabel("Arrow keys")
        .accessibilityAction(named: "Up") { onDirection(KeyBytes.up) }
        .accessibilityAction(named: "Down") { onDirection(KeyBytes.down) }
        .accessibilityAction(named: "Left") { onDirection(KeyBytes.left) }
        .accessibilityAction(named: "Right") { onDirection(KeyBytes.right) }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let dx = g.translation.width
                    let dy = g.translation.height
                    let dist = sqrt(dx * dx + dy * dy)
                    let limit = radius - knobSize / 2
                    let scale = (dist > limit && dist > 0) ? limit / dist : 1
                    knob = CGSize(width: dx * scale, height: dy * scale)
                    setDirection(direction(dx: dx, dy: dy))
                }
                .onEnded { _ in
                    knob = .zero
                    setDirection(nil)
                }
        )
        .onDisappear { repeatTask?.cancel() }
    }

    private func direction(dx: CGFloat, dy: CGFloat) -> [UInt8]? {
        if abs(dx) < deadZone && abs(dy) < deadZone { return nil }
        if abs(dx) > abs(dy) { return dx > 0 ? KeyBytes.right : KeyBytes.left }
        return dy > 0 ? KeyBytes.down : KeyBytes.up
    }

    private func setDirection(_ dir: [UInt8]?) {
        guard dir != currentDir else { return }
        currentDir = dir
        repeatTask?.cancel()
        guard let dir else { return }
        repeatTask = Task { @MainActor in
            while !Task.isCancelled {
                onDirection(dir)
                UISelectionFeedbackGenerator().selectionChanged()
                try? await Task.sleep(for: .milliseconds(160))
            }
        }
    }
}
