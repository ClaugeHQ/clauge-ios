import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// UIKit delegate for Firebase + push. Wired into SwiftUI via
/// `@UIApplicationDelegateAdaptor`. Configures Firebase only when a
/// `GoogleService-Info.plist` is bundled, so the app still runs without it
/// (push simply stays inert) — mirroring the Android google-services.json
/// behaviour.
final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
        }
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            PushManager.requestAuthorizationIfEnabled()
            PushManager.syncTokenToDesktop()
        }
        return true
    }

    // MARK: APNs

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No APNs token — push won't work, but the app is fully usable.
    }

    // MARK: FCM

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            Services.shared.store.fcmToken = fcmToken
            PushManager.syncTokenToDesktop()
        }
    }

    // MARK: Foreground presentation + taps

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let terminalId = info["terminalId"] as? String, !terminalId.isEmpty else { return }
        let serverName = info["serverName"] as? String
        await MainActor.run {
            Services.shared.push.deliver(DeepLink(terminalId: terminalId, serverName: serverName))
        }
    }
}
