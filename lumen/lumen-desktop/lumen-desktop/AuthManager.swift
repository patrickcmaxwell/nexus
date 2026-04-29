import Foundation
import WebKit
import Combine

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false

    private var nexusBase: String { LumenAPIManager.shared.nexusBase }

    // Called by NativePinView or FaceWebView on successful auth
    func handleSessionCookie(_ value: String) {
        LumenAPIManager.shared.sessionCookie = value
        isAuthenticated = true
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
