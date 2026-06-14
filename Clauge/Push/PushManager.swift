import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging

/// Notification permission + FCM token registration. The desktop pushes via
/// FCM, so we obtain an FCM registration token and POST it to
/// `/v1/device/fcm`. Best-effort: failures are swallowed (push is additive).
enum PushManager {
    /// Ask for notification permission (if the user hasn't opted out) and
    /// register for remote notifications so APNs → FCM token flow starts.
    @MainActor
    static func requestAuthorizationIfEnabled() {
        guard Services.shared.store.notificationsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Push the cached FCM token to the active desktop. Called when a token
    /// arrives, on app start, and after (re)pairing.
    @MainActor
    static func syncTokenToDesktop() {
        let store = Services.shared.store
        guard store.notificationsEnabled, store.isPaired else { return }
        guard let token = store.fcmToken, !token.isEmpty else {
            // No cached token yet — ask FCM for one; the delegate caches + retries.
            Messaging.messaging().token { value, _ in
                if let value { Task { @MainActor in store.fcmToken = value; syncTokenToDesktop() } }
            }
            return
        }
        Task {
            try? await Services.shared.client.registerFcm(token: token)
        }
    }
}
