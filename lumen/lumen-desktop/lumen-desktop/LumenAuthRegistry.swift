import Foundation
import Combine
import SwiftUI

/// Multi-user identity registry for Lumen. Lives above the SwiftUI view tree
/// (owned by App root) so user switching survives every navigation.
///
/// Mental model: one Mac, multiple humans. Each authenticated human's
/// `nx_session` cookie lives in macOS Keychain under the same service so
/// switching is "swap the active humanId, pull the cookie, hand it to
/// LumenAPIManager, tell LumenStore to flush + refetch."
///
/// - `knownSessions`: every human who has ever logged in on this device
///   and hasn't been signed-out. Cookies for these humans live in Keychain.
/// - `activeHuman`: the human whose context is currently driving the app.
///   nil = nobody's signed in (AuthGate visible).
/// - PIN re-verify on switch: the cached cookie is NOT trusted for switching.
///   The Director must enter the target human's PIN, which calls
///   /api/auth/switch on the server. Server invalidates the prior session
///   and issues a fresh one.
///
/// Wire this in App.init alongside LumenStore + AuthManager. LumenStore
/// observes `activeHuman` changes and calls its own reload pipeline.
@MainActor
final class LumenAuthRegistry: ObservableObject {
    @Published private(set) var knownSessions: [StoredAuthSession] = []
    @Published private(set) var activeHuman: ActiveHumanProfile? = nil

    /// Set by the App root — fires whenever the active human changes
    /// (login, switch, restore-from-Keychain). LumenStore uses this hook
    /// to flush per-user state and refetch under the new identity.
    var onActiveHumanChanged: ((ActiveHumanProfile?) -> Void)?

    /// Persisted across launches — the humanId of the session that was
    /// active when the app last quit. On launch we restore from this.
    @AppStorage("lumen.auth.activeHumanId") private var activeHumanIdStored: String = ""

    private let metadataAccountSuffix = ".meta"

    init() {
        loadKnownFromKeychain()
    }

    // MARK: Bootstrap

    /// Load every cached session from Keychain. Called at init. Each known
    /// session has TWO Keychain entries: `<humanId>` for the cookie value,
    /// `<humanId>.meta` for JSON-encoded profile (display_name, email, etc).
    private func loadKnownFromKeychain() {
        let accounts = KeychainStore.allAccounts()
        let humanIds = Set(accounts
            .filter { !$0.hasSuffix(metadataAccountSuffix) }
            .filter { UUID(uuidString: $0) != nil })

        knownSessions = humanIds.compactMap { id -> StoredAuthSession? in
            guard let metaJson = KeychainStore.get(id + metadataAccountSuffix),
                  let metaData = metaJson.data(using: .utf8),
                  let meta = try? JSONDecoder().decode(StoredAuthSession.self, from: metaData)
            else { return nil }
            return meta
        }
        // Most-recent first
        knownSessions.sort { $0.lastActiveAt > $1.lastActiveAt }
    }

    /// On app launch, attempt to restore the active session. Returns true
    /// if a valid session was found and applied to LumenAPIManager. Calls
    /// /api/auth/me to verify the cookie is still valid server-side.
    func restoreActiveSession() async -> Bool {
        guard !activeHumanIdStored.isEmpty,
              let session = knownSessions.first(where: { $0.humanId == activeHumanIdStored }),
              let cookie = KeychainStore.get(session.humanId)
        else { return false }

        LumenAPIManager.shared.sessionCookie = cookie
        if let profile = await fetchActiveProfile() {
            activeHuman = profile
            return true
        }
        // Cookie present but server rejected — drop it
        LumenAPIManager.shared.sessionCookie = nil
        return false
    }

    // MARK: Login / sign-up

    /// Called when an AuthGate flow (face or PIN) returns a fresh cookie.
    /// Fetches the human's profile, adds them to known sessions, persists
    /// the cookie in Keychain, makes them active.
    func adoptFreshSession(cookie: String) async {
        LumenAPIManager.shared.sessionCookie = cookie
        guard let profile = await fetchActiveProfile() else { return }
        await rememberAndActivate(profile: profile, cookie: cookie)
    }

    // MARK: Switching

    /// Switch to a known human. Requires a fresh PIN — calls /api/auth/switch
    /// on the server, which invalidates the prior session and issues a new one.
    /// On success, swaps the active cookie + flips activeHuman.
    func switchUser(toEmail email: String, pin: String) async throws {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/auth/switch") else {
            throw AuthError.network
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Lumen-Client")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "pin": pin])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.invalidCredentials
        }

        // Pull the new nx_session cookie out of the Set-Cookie header. The
        // server doesn't echo it in the body for /switch — only /pin does.
        let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        guard let newCookie = parseSessionCookie(setCookie) else {
            // Fallback: maybe body has it via the X-Lumen-Client path
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let bodyCookie = body?["sessionId"] as? String, !bodyCookie.isEmpty {
                LumenAPIManager.shared.sessionCookie = bodyCookie
            } else {
                throw AuthError.network
            }
            return
        }

        LumenAPIManager.shared.sessionCookie = newCookie
        guard let profile = await fetchActiveProfile() else { throw AuthError.network }
        await rememberAndActivate(profile: profile, cookie: newCookie)
    }

    /// Switch to a known human via cached cookie ONLY (no PIN re-verify).
    /// Used when the cached session is still valid server-side. Returns
    /// false if the cached cookie has expired and the Director needs to
    /// re-enter their PIN.
    func switchUserViaCachedCookie(humanId: String) async -> Bool {
        guard let cookie = KeychainStore.get(humanId) else { return false }
        LumenAPIManager.shared.sessionCookie = cookie
        guard let profile = await fetchActiveProfile() else {
            LumenAPIManager.shared.sessionCookie = nil
            return false
        }
        await rememberAndActivate(profile: profile, cookie: cookie)
        return true
    }

    // MARK: Sign out

    /// Sign out the active human. Invalidates the session server-side, drops
    /// the Keychain entries, removes from known sessions. Caller usually
    /// then routes back to AuthGate.
    func signOutActive() async {
        guard let active = activeHuman else { return }
        let base = LumenAPIManager.shared.nexusBase
        if let url = URL(string: "\(base)/api/security/logout"),
           let cookie = LumenAPIManager.shared.sessionCookie {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
            _ = try? await URLSession.shared.data(for: req)
        }
        forgetSession(humanId: active.humanId)
    }

    /// Forget a known session (invalidates cookie locally only — does NOT
    /// hit the server). Used for the "remove from this device" action.
    func forgetSession(humanId: String) {
        KeychainStore.delete(humanId)
        KeychainStore.delete(humanId + metadataAccountSuffix)
        knownSessions.removeAll { $0.humanId == humanId }
        if activeHuman?.humanId == humanId {
            activeHuman = nil
            activeHumanIdStored = ""
            LumenAPIManager.shared.sessionCookie = nil
            onActiveHumanChanged?(nil)
        }
    }

    // MARK: Internals

    /// Fetch /api/auth/me with whatever cookie is currently in
    /// LumenAPIManager.shared. Returns nil on 401/network error.
    private func fetchActiveProfile() async -> ActiveHumanProfile? {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/auth/me"),
              let cookie = LumenAPIManager.shared.sessionCookie
        else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return ActiveHumanProfile(
                humanId:     json["humanId"]     as? String ?? "",
                email:       json["email"]       as? String ?? "",
                displayName: json["displayName"] as? String ?? "",
                handle:      json["handle"]      as? String,
                role:        json["role"]        as? String ?? "observer",
                isOwner:     json["isOwner"]     as? Bool   ?? false
            )
        } catch {
            return nil
        }
    }

    /// Persist + activate. Called from every login path (initial PIN/face,
    /// switch, restore). Stores cookie + profile JSON in Keychain, sets
    /// activeHumanIdStored, updates @Published state.
    private func rememberAndActivate(profile: ActiveHumanProfile, cookie: String) async {
        let session = StoredAuthSession(
            humanId: profile.humanId,
            email: profile.email,
            displayName: profile.displayName,
            handle: profile.handle,
            role: profile.role,
            isOwner: profile.isOwner,
            lastActiveAt: Date()
        )
        KeychainStore.set(cookie, account: profile.humanId)
        if let metaData = try? JSONEncoder().encode(session),
           let metaJson = String(data: metaData, encoding: .utf8) {
            KeychainStore.set(metaJson, account: profile.humanId + metadataAccountSuffix)
        }
        activeHumanIdStored = profile.humanId

        // Move to top of known list
        knownSessions.removeAll { $0.humanId == profile.humanId }
        knownSessions.insert(session, at: 0)
        activeHuman = profile
        onActiveHumanChanged?(profile)
    }

    /// Pull the value of nx_session out of a Set-Cookie header string.
    /// Format: "nx_session=<value>; Path=/; HttpOnly; Secure; SameSite=None".
    private func parseSessionCookie(_ header: String) -> String? {
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "nx_session" {
                return kv[1]
            }
        }
        return nil
    }
}

// MARK: - Models

struct ActiveHumanProfile: Identifiable, Equatable {
    var id: String { humanId }
    let humanId: String
    let email: String
    let displayName: String
    let handle: String?
    let role: String
    let isOwner: Bool

    var avatarInitial: String {
        let first = displayName.first ?? email.first ?? "?"
        return String(first).uppercased()
    }
}

struct StoredAuthSession: Codable, Identifiable, Equatable {
    var id: String { humanId }
    let humanId: String
    let email: String
    let displayName: String
    let handle: String?
    let role: String
    let isOwner: Bool
    var lastActiveAt: Date
}

enum AuthError: Error {
    case invalidCredentials
    case network
    case unknown
}
