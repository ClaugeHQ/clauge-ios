import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var router: Router
    @StateObject private var vm = DevicesViewModel()

    @State private var showPair = false
    @State private var pairBaselineActive: String?
    @State private var removeTarget: Device?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
        }
        // Custom header keeps the "Clauge" wordmark and the gear on the
        // same row (a large nav title would drop the title below the bar
        // buttons, leaving them misaligned).
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPair) {
            NavigationStack { WelcomeView() }
                .tint(Theme.pink)
        }
        .onChange(of: store.activeDeviceId) { newValue in
            if showPair && newValue != pairBaselineActive { showPair = false }
        }
        .confirmationDialog(
            "Remove \(removeTarget?.name ?? "")?",
            isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let t = removeTarget { store.removeDevice(t.id) }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("You'll need to pair again to control this desktop.")
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Clauge")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if !store.devices.isEmpty {
                headerButton("plus") { startPairing() }
            }
            headerButton("gearshape") { router.push(.settings) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.devices.isEmpty {
            EmptyDevices(onAdd: startPairing)
        } else {
            List {
                ForEach(store.devices) { device in
                    DeviceRow(device: device,
                              status: vm.online[device.id],
                              onDetails: { openDetails(device) })
                        .listRowBackground(Theme.surface)
                        .contentShape(Rectangle())
                        .onTapGesture { tap(device) }
                        .swipeActions {
                            Button(role: .destructive) { removeTarget = device } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.refresh() }
        }
    }

    private func headerButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.pink)
                .frame(width: 40, height: 40)
                .background(Theme.surfaceHigh, in: Circle())
                .overlay(Circle().stroke(Theme.outlineVariant, lineWidth: 1))
        }
    }

    private func tap(_ device: Device) {
        store.setActive(device.id)
        // Online → open the cockpit. Offline → re-probe in place; never dead-end.
        if vm.online[device.id] == false {
            Task { await vm.refresh() }
        } else {
            router.push(.cockpit)
        }
    }

    private func openDetails(_ device: Device) {
        store.setActive(device.id)
        router.push(.deviceInfo)
    }

    private func startPairing() {
        pairBaselineActive = store.activeDeviceId
        showPair = true
    }
}

private struct EmptyDevices: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("No devices yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Pair your desktop from Settings → Mobile to control it from here.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onAdd) {
                Label("Add device", systemImage: "plus")
                    .font(.headline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
            }
            .background(Theme.pink, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Theme.background)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeviceRow: View {
    let device: Device
    let status: Bool?
    let onDetails: () -> Void

    private var online: Bool { status == true }

    private var dotColor: Color {
        switch status {
        case .some(true): return Theme.deviceOnline
        case .some(false): return Theme.deviceOffline
        case .none: return Theme.deviceChecking
        }
    }

    private var statusLabel: String {
        switch status {
        case .some(true): return "Online"
        case .some(false): return "Offline"
        case .none: return "Checking…"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(color: dotColor, diameter: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(statusLabel) · Port \(device.port)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            // Metrics are only meaningful for a reachable device.
            Button(action: onDetails) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!online)
            .opacity(online ? 1 : 0.4)
        }
        .padding(.vertical, 6)
        .opacity(online ? 1 : 0.55)
    }
}
