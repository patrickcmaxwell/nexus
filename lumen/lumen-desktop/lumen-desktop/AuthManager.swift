import Foundation
import WebKit
import Combine

/// Lightweight auth state holder. The actual identity lives in
/// `LumenAuthRegistry` (Operation Multi-User) — this class is just the
/// `isAuthenticated` boolean that drives whether MainView or AuthGate is
/// visible, plus the bridge that lets registry observe cookie adoption.
@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false

    /// Hooks the App root injects so any cookie that lands via face/PIN/
    /// passphrase flows is also adopted as a multi-user session.
    var onCookieAdopted: ((String) -> Void)?
    var onSignOut: (() -> Void)?

    private var nexusBase: String { LumenAPIManager.shared.nexusBase }

    /// Called by NativePinView, FaceWebView, or any other auth path on success.
    /// Wires the cookie into LumenAPIManager and notifies the registry so
    /// the human's profile gets fetched + cached in Keychain.
    func handleSessionCookie(_ value: String) {
        LumenAPIManager.shared.sessionCookie = value
        isAuthenticated = true
        onCookieAdopted?(value)
    }

    func signOut() {
        Task {
            // Invalidate session server-side
            if let cookie = LumenAPIManager.shared.sessionCookie,
               let url = URL(string: "\(nexusBase)/api/security/logout") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
                try? await URLSession.shared.data(for: req)
            }

            // Clear WKWebView cookies so face page starts fresh
            await clearWebViewCookies()

            LumenAPIManager.shared.sessionCookie = nil
            UserDefaults.standard.removeObject(forKey: "lumen.currentConversationId")
            isAuthenticated = false
            onSignOut?()
        }
    }

    private func clearWebViewCookies() async {
        await withCheckedContinuation { continuation in
            let dataStore = WKWebsiteDataStore.default()
            dataStore.httpCookieStore.getAllCookies { cookies in
                let group = DispatchGroup()
                cookies.forEach { cookie in
                    group.enter()
                    dataStore.httpCookieStore.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) { continuation.resume() }
            }
        }
    }
}
