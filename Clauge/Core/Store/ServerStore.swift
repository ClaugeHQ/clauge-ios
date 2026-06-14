import Foundation
import SwiftUI
import UIKit

/// Single source of truth for paired desktops, the active device, secrets,
/// and user settings. Non-secret state lives in UserDefaults; pairing
/// tokens and the FCM token live in the Keychain.
@MainActor
final class ServerStore: ObservableObject {
    static let defaultPort = 7431

    @Published private(set) var devices: [Device] = []
    @Published private(set) var activeDeviceId: String?
    @Published var deviceName: String { didSet { if loaded { defaults.set(deviceName, forKey: Key.deviceName) } } }
    @Published var notificationsEnabled: Bool { didSet { if loaded { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } } }
    @Published var onboarded: Bool { didSet { if loaded { defaults.set(onboarded, forKey: Key.onboarded) } } }

    private let defaults = UserDefaults.standard
    private var loaded = false

    private enum Key {
        static let devices = "devices"
        static let activeDeviceId = "activeDeviceId"
        static let deviceName = "deviceName"
        static let notificationsEnabled = "notificationsEnabled"
        static let onboarded = "onboarded"
    }

    init() {
        if let data = defaults.data(forKey: Key.devices),
           let decoded = try? JSONDecoder().decode([Device].self, from: data) {
            devices = decoded
        }
        activeDeviceId = defaults.string(forKey: Key.activeDeviceId)
        deviceName = defaults.string(forKey: Key.deviceName) ?? UIDevice.current.name
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        onboarded = defaults.bool(forKey: Key.onboarded)
        loaded = true
    }

    // MARK: Derived

    var activeDevice: Device? { devices.first { $0.id == activeDeviceId } }
    var isPaired: Bool { activeDevice != nil }

    func deviceId(byName name: String) -> String? { devices.first { $0.name == name }?.id }

    // MARK: Secrets

    func token(for deviceId: String) -> String? { Keychain.get("deviceToken:\(deviceId)") }
    var activeToken: String? { activeDeviceId.flatMap { token(for: $0) } }

    var fcmToken: String? {
        get { Keychain.get("fcmToken") }
        set { Keychain.set(newValue, for: "fcmToken") }
    }

    // MARK: Mutations

    func setActive(_ id: String?) {
        activeDeviceId = id
        defaults.set(id, forKey: Key.activeDeviceId)
    }

    /// Add a new device, or merge into an existing one with the same name
    /// (union the host list, refresh the token). Makes it active.
    @discardableResult
    func addOrMergeDevice(name: String, hosts: [String], port: Int, token: String) -> Device {
        let device: Device
        if let idx = devices.firstIndex(where: { $0.name == name }) {
            var d = devices[idx]
            for h in hosts where !d.hosts.contains(h) { d.hosts.append(h) }
            d.port = port
            devices[idx] = d
            device = d
        } else {
            device = Device(id: UUID().uuidString, name: name, hosts: hosts, port: port,
                            addedAt: Date().timeIntervalSince1970)
            devices.append(device)
        }
        Keychain.set(token, for: "deviceToken:\(device.id)")
        persistDevices()
        setActive(device.id)
        return device
    }

    func removeDevice(_ id: String) {
        Keychain.remove("deviceToken:\(id)")
        devices.removeAll { $0.id == id }
        persistDevices()
        if activeDeviceId == id { setActive(devices.first?.id) }
    }

    /// Invoked on a 401 from the active device: its token is no longer valid,
    /// so drop it and fall back to any other paired device (or none).
    func clearActiveDevice() {
        guard let id = activeDeviceId else { return }
        removeDevice(id)
    }

    /// Full disconnect — forget every paired device and its token.
    func clear() {
        for d in devices { Keychain.remove("deviceToken:\(d.id)") }
        devices.removeAll()
        persistDevices()
        setActive(nil)
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Key.devices)
        }
    }
}
