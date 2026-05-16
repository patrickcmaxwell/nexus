// NexusPushClient.swift
//
// Holds the APNs device token after the OS hands it to AppDelegate, posts
// it to nexus-web's /api/push/devices, and exposes a `sendTestPush` so
// Settings can trigger an end-to-end probe.
//
// Why a separate object (and not just inlined in AppDelegate): the
// registration needs the current preference toggles + auth session, both of
// which live in the SwiftUI side. This client is the bridge.

import Foundation
import UIKit
import UserNotifications

@MainActor
final class NexusPushClient: ObservableObject {
    static let shared = NexusPushClient()

    @Published private(set) var deviceTokenHex: String? = UserDefaults.standard.string(forKey: "nexus.push.deviceTokenHex")
    @Published private(set) var lastRegisteredAt: Date? = UserDefaults.standard.object(forKey: "nexus.push.lastRegisteredAt") as? Date
    @Published var lastError: String?
    /// Deep-link string from the most recent tapped notification. ContentView
    /// reads + clears this on appear so it can route the user appropriately.
    @Published var pendingDeepLink: String?

    private init() {}

    // MARK: - Permission + registration kickoff

    /// Asks for OS permission, then (if granted) tells UIApplication to
    /// register for remote notifications. AppDelegate receives the token
    /// asynchronously and calls back into `handleNewDeviceToken`.
    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return false }
            UIApplication.shared.registerForRemoteNotifications()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// AppDelegate calls this with the hex-encoded token. Cache locally,
    /// then push to the server with current prefs.
    nonisolated func handleNewDeviceToken(_ hex: String) {
        Task { @MainActor in
            self.deviceTokenHex = hex
            UserDefaults.standard.set(hex, forKey: "nexus.push.deviceTokenHex")
            await self.registerWithServer()
        }
    }

    /// POST the cached token to nexus-web. Re-registering is cheap (server
    /// upserts on (human_id, token)) and is the right thing to do when:
    ///   - app cold-starts (in case the token rotated)
    ///   - the user toggles a preference (so server-side filters update)
    func registerWithServer() async {
        guard let hex = deviceTokenHex else { return }
        let prefs: [String: Bool] = [
            "agentDone":      UserDefaults.standard.bool(forKey: "nexus.notify.agentDone"),
            "scheduleFired":  UserDefaults.standard.bool(forKey: "nexus.notify.scheduleFired"),
            "researchDone":   UserDefaults.standard.bool(forKey: "nexus.notify.researchDone"),
            "opUpdated":      UserDefaults.standard.bool(forKey: "nexus.notify.opUpdated"),
            "terminalAlert":  UserDefaults.standard.bool(forKey: "nexus.notify.terminalAlert"),
        ]
        let body: [String: Any] = [
            "platform":     "ios",
            "token":        hex,
            "bundleId":     Bundle.main.bundleIdentifier ?? "",
            "deviceLabel":  await Self.deviceLabel(),
            "prefs":        prefs,
        ]
        do {
            _ = try await NexusPushClient.postJSON(path: "/api/push/devices", body: body)
            self.lastRegisteredAt = Date()
            UserDefaults.standard.set(self.lastRegisteredAt, forKey: "nexus.push.lastRegisteredAt")
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Pushes the SAME device row but updates prefs. Called when the user
    /// flips a toggle in Settings so server-side filters stay in sync
    /// without waiting for the next cold start.
    func syncPreferences() async {
        await registerWithServer()
    }

    /// Pull the token off the server (and stop further pushes here).
    func unregister() async {
        guard let hex = deviceTokenHex else { return }
        do {
            _ = try await NexusPushClient.postJSON(path: "/api/push/devices", body: ["token": hex], method: "DELETE")
            self.deviceTokenHex = nil
            UserDefaults.standard.removeObject(forKey: "nexus.push.deviceTokenHex")
            UserDefaults.standard.removeObject(forKey: "nexus.push.lastRegisteredAt")
            self.lastRegisteredAt = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Triggers a server-side test push at this human. Returns the dispatch
    /// breakdown ("sent N · skipped M · failed K") so the UI can show it.
    func sendTestPush() async throws -> (sent: Int, skipped: Int, failed: Int) {
        let resp = try await NexusPushClient.postJSON(path: "/api/push/test", body: [:])
        let sent    = (resp["sent"] as? Int) ?? 0
        let skipped = (resp["skipped"] as? Int) ?? 0
        let failed  = (resp["failed"] as? Int) ?? 0
        return (sent, skipped, failed)
    }

    // MARK: - Helpers

    private static func deviceLabel() async -> String {
        let device = await MainActor.run { UIDevice.current.name }
        return device
    }

    /// Shared JSON POST helper. Uses NexusAPIClient's base URL + session
    /// id so the request carries the same auth as everything else on iOS.
    private static func postJSON(
        path: String,
        body: [String: Any],
        method: String = "POST",
    ) async throws -> [String: Any] {
        let api = NexusAPIClient.shared
        guard let sid = api.sessionId, !sid.isEmpty else {
            throw NSError(domain: "NexusPush", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let url = URL(string: "\(api.nexusBase)\(path)") else {
            throw NSError(domain: "NexusPush", code: 400, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        if !body.isEmpty {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            // Some servers require Content-Length on POSTs even with empty
            // bodies — sending "{}" is harmless and avoids HTTP/2 quirks.
            req.httpBody = "{}".data(using: .utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "NexusPush", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw NSError(domain: "NexusPush", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
