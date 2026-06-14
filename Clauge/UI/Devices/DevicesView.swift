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
                List {
                    ForEach(store.devices) { device in
                        DeviceRow(device: device, status: vm.online[device.id])
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

                VersionFooter()
            }
        }
        .navigationTitle("Devices")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { startPairing() } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { router.push(.settings) } label: { Image(systemName: "gearshape") }
            }
        }
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

    private func tap(_ device: Device) {
        store.setActive(device.id)
        if vm.online[device.id] == false {
            Task { await vm.refresh() }
        } else {
            router.push(.home)
        }
    }

    private func startPairing() {
        pairBaselineActive = store.activeDeviceId
        showPair = true
    }
}

private struct DeviceRow: View {
    let device: Device
    let status: Bool?

    private var dotColor: Color {
        switch status {
        case .some(true): return Theme.deviceOnline
        case .some(false): return Theme.deviceOffline
        case .none: return Theme.deviceChecking
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(color: dotColor, diameter: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text("Port \(device.port) · \(device.hosts.count) address\(device.hosts.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 6)
    }
}
