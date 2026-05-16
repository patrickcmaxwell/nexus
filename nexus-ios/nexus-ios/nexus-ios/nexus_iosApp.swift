import SwiftUI
import UIKit
import UserNotifications

@main
struct nexus_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// App delegate exists exclusively to receive the APNs device token. Pure
/// SwiftUI Apps can't get this — the OS only hands it to a UIApplicationDelegate.
/// On token receipt we hand it to NexusPushClient which (a) caches it locally
/// for the Settings UI to display, (b) POSTs it to /api/push/devices so the
/// server can route notifications here.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Re-register on every cold start when the user has previously
        // opted in. If permission was already granted, this gets us a
        // fresh token without prompting; if not, it's a no-op until the
        // user enables in Settings.
        if UserDefaults.standard.bool(forKey: "nexus.notify.enabled") {
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        NexusPushClient.shared.handleNewDeviceToken(hex)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
    ) {
        NexusPushClient.shared.lastError = error.localizedDescription
    }

    // Show banner + sound even when the app is foregrounded, otherwise iOS
    // silently swallows the notification when something fires while the
    // user is staring at the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // Tap-handling. Server encodes a deep-link string in `link` (e.g.
    // "nexus://operations/<id>"). We stash it on NexusPushClient and
    // ContentView reads + clears it to navigate when the app comes up.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let info = response.notification.request.content.userInfo
        if let link = info["link"] as? String {
            NexusPushClient.shared.pendingDeepLink = link
        }
        completionHandler()
    }
}
