import SwiftUI

/// System Monitor for the active device — host card, a 2×2 metric grid, CPU and
/// memory trend sparklines, and per-volume storage. Pushed via `.deviceInfo`.
struct DeviceInfoView: View {
    @EnvironmentObject private var store: ServerStore
    @StateObject private var vm = SysMonViewModel()

    private var deviceName: String { store.activeDevice?.name ?? "Device" }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .navigationTitle(deviceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { vm.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(Theme.pink)
            }
        }
        .task { vm.start() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if let m = vm.metrics {
            metricsList(m)
        } else if let err = vm.error {
            errorState(err)
        } else {
            ProgressView()
                .tint(Theme.pink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { vm.refresh() }
                .font(.headline)
                .padding(.vertical, 10)
                .padding(.horizontal, 24)
                .background(Theme.pink, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Theme.background)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricsList(_ m: SysMetricsDto) -> some View {
        let memPct = m.memory.totalBytes > 0
            ? Double(m.memory.usedBytes) / Double(m.memory.totalBytes) * 100
            : 0
        let primary = m.volumes.max { $0.totalBytes < $1.totalBytes }
        let storagePct: Double = {
            guard let v = primary, v.totalBytes > 0 else { return 0 }
            return Double(v.usedBytes) / Double(v.totalBytes) * 100
        }()

        return ScrollView {
            LazyVStack(spacing: 12) {
                if let err = vm.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Theme.onErrorContainer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Theme.errorContainer, in: RoundedRectangle(cornerRadius: 8))
                }

                HostHeader(m: m)

                HStack(spacing: 12) {
                    MetricCard(title: "CPU", value: "\(Int(m.cpu.usagePct.rounded()))%",
                               sub: cpuLabel(m.cpu.usagePct), accent: Accent.blue)
                    MetricCard(title: "Memory", value: "\(Int(memPct.rounded()))%",
                               sub: "\(formatBytes(m.memory.availableBytes)) free", accent: Accent.purple)
                }
                HStack(spacing: 12) {
                    MetricCard(title: "Storage", value: "\(Int(storagePct.rounded()))%",
                               sub: storageLabel(storagePct), accent: Accent.amber)
                    MetricCard(title: "Uptime", value: formatUptime(m.uptimeSecs),
                               sub: "Since reboot", accent: Accent.green)
                }

                GraphCard(title: "CPU load", sub: "\(m.cpu.brand) · \(m.cpu.cores) cores",
                          history: vm.cpuHistory, color: Accent.blue)
                GraphCard(title: "Memory",
                          sub: "\(formatBytes(m.memory.usedBytes)) of \(formatBytes(m.memory.totalBytes)) used",
                          history: vm.memHistory, color: Accent.purple)

                Text("Storage")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.leading, 4)

                ForEach(m.volumes) { v in
                    VolumeCard(volume: v)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Components

private enum Accent {
    static let green = Color(hex: "#34D399")
    static let blue = Color(hex: "#60A5FA")
    static let amber = Color(hex: "#E0A042")
    static let purple = Color(hex: "#A78BFA")
}

private struct HostHeader: View {
    let m: SysMetricsDto
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.serverName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(m.platform)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let b = m.battery {
                BatteryChip(battery: b)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BatteryChip: View {
    let battery: BatteryDto
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: battery.charging ? "battery.100.bolt" : "battery.100")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(battery.charging ? Accent.green : Theme.textSecondary)
            Text("\(battery.percent)%")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let sub: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
            Text(sub)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct GraphCard: View {
    let title: String
    let sub: String
    let history: [Double]
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(sub)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Sparkline(values: history, color: color)
                .frame(height: 56)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count >= 2 else { return }
                let w = geo.size.width
                let h = geo.size.height
                let stepX = w / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let clamped = min(max(CGFloat(v), 0), 100)
                    let x = stepX * CGFloat(i)
                    let y = h * (1 - clamped / 100)
                    let point = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, lineWidth: 2)
        }
    }
}

private struct VolumeCard: View {
    let volume: VolumeDto
    private var fraction: Double {
        volume.totalBytes > 0 ? Double(volume.usedBytes) / Double(volume.totalBytes) : 0
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(volume.name)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(volume.mountPoint)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            ProgressView(value: fraction)
                .tint(fraction > 0.85 ? Theme.error : Theme.pink)
            Text("\(formatBytes(volume.usedBytes)) used of \(formatBytes(volume.totalBytes)) · \(formatBytes(volume.availableBytes)) free")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Formatting

private func formatBytes(_ bytes: Int) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1000 {
        return String(format: "%.1f TB", gb / 1000)
    }
    return String(format: "%.1f GB", gb)
}

private func formatUptime(_ secs: Int) -> String {
    let days = secs / 86_400
    let hours = (secs % 86_400) / 3_600
    let mins = (secs % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(mins)m"
}

private func cpuLabel(_ pct: Double) -> String {
    if pct < 30 { return "Light" }
    if pct < 70 { return "Moderate" }
    return "Heavy"
}

private func storageLabel(_ pct: Double) -> String {
    pct > 85 ? "Running low" : "Healthy"
}
