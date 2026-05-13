// NexusAPIClient.swift
// Nexus iOS — talks to nexus-web's Eve API. Mirrors the LumenAPIManager
// pattern but slimmed down for the phone:
// - Auth: PIN → Bearer sessionId (same X-Lumen-Client flow)
// - Brain: POST /api/eve with the sessionId, returns Eve's reply
// - Base URL is configurable; defaults to home-LAN, falls back to public host
//
// Note: phone is mobile, so the public host is what matters in practice.
// Override `nexusBase` from a settings UI when on home wifi to use the
// LAN IP and avoid going over the internet round-trip.

import Foundation

class NexusAPIClient {
    static let shared = NexusAPIClient()

    static let publicBase = "https://portal.maxnexus.io"

    /// User-overridable via UserDefaults (`nexus.baseURL`). Falls back to public host.
    var nexusBase: String {
        UserDefaults.standard.string(forKey: "nexus.baseURL") ?? Self.publicBase
    }

    /// Optional direct-to-LAN Ollama URL. When set, `askLocalDirect` skips
    /// nexus-web entirely and POSTs straight to the home Mac's Ollama
    /// daemon for sub-second on-wifi responses. Example value:
    /// `http://192.168.1.50:11434/v1/chat/completions`.
    var localBrainURL: String? {
        get {
            let v = UserDefaults.standard.string(forKey: "nexus.localBrainURL") ?? ""
            return v.isEmpty ? nil : v
        }
        set {
            if let v = newValue, !v.isEmpty { UserDefaults.standard.set(v, forKey: "nexus.localBrainURL") }
            else { UserDefaults.standard.removeObject(forKey: "nexus.localBrainURL") }
        }
    }

    var localBrainModel: String {
        UserDefaults.standard.string(forKey: "nexus.localBrainModel") ?? "llama3.2:3b"
    }

    /// ElevenLabs voice id used for /api/eve/tts. Default Bella.
    var voiceId: String {
        get { UserDefaults.standard.string(forKey: "nexus.voiceId") ?? "EXAVITQu4vr4xnSDxMaL" }
        set { UserDefaults.standard.set(newValue, forKey: "nexus.voiceId") }
    }

    private static let sessionKey = "nexus.sessionId"           // legacy UserDefaults key (migrated)
    private static let keychainSessionAccount = "session.active" // current Keychain slot

    /// Bearer token for the active Nexus session. Stored in Keychain so it
    /// survives reinstall and isn't included in iCloud unencrypted backups.
    /// On first read after upgrade, transparently migrates a value still
    /// sitting in UserDefaults so existing users don't get logged out.
    var sessionId: String? {
        get {
            if let kc = KeychainHelper.read(account: Self.keychainSessionAccount), !kc.isEmpty {
                return kc
            }
            // Legacy fallback: drain UserDefaults into Keychain on first hit.
            if let legacy = UserDefaults.standard.string(forKey: Self.sessionKey), !legacy.isEmpty {
                KeychainHelper.save(legacy, account: Self.keychainSessionAccount)
                UserDefaults.standard.removeObject(forKey: Self.sessionKey)
                return legacy
            }
            return nil
        }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainHelper.save(v, account: Self.keychainSessionAccount)
            } else {
                KeychainHelper.delete(account: Self.keychainSessionAccount)
            }
            // Belt-and-suspenders: clear the legacy key whenever we set/clear.
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        }
    }

    enum APIError: Error { case invalidURL, unauthorized, requestFailed(String) }

    /// Active human's identity, fetched from /api/auth/me. Mirrors the
    /// shape Lumen/web use so the iOS UI can render the same avatar +
    /// role hints with no schema friction.
    struct ActiveProfile: Equatable {
        let humanId: String
        let email: String
        let displayName: String
        let role: String
        let isOwner: Bool

        var avatarInitial: String {
            String((displayName.first ?? email.first ?? "?")).uppercased()
        }
    }

    // MARK: - Auth

    /// Identity-first sign-in. Sends email + 4-digit PIN to /api/security/pin.
    /// On success returns the session id and caches it. The X-Lumen-Client
    /// header makes the server echo the sessionId in the response body so we
    /// can stash it without doing cookie parsing on iOS.
    func authenticate(email: String, pin: String) async throws -> String {
        guard let url = URL(string: "\(nexusBase)/api/security/pin") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1",                forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email":    email,
            "pin":      pin,
            "remember": true,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }

        let bodyJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        // Server-side prints the exact error code (UNKNOWN_EMAIL / WRONG_PIN /
        // ACCOUNT_LOCKED / etc) so we can show the user *why* not just *that*.
        NSLog("[nexus-auth] POST %@ -> %d body=%@", url.absoluteString, http.statusCode, bodyText)

        if http.statusCode == 401 {
            // Surface server's specific error code so the user knows whether
            // it's the email, the PIN, or an account state issue.
            if let code = bodyJSON?["error"] as? String {
                throw APIError.requestFailed(code)
            }
            throw APIError.unauthorized
        }
        guard http.statusCode == 200 else {
            let serverMsg = (bodyJSON?["error"] as? String) ?? "status \(http.statusCode)"
            throw APIError.requestFailed(serverMsg)
        }
        guard let sid = bodyJSON?["sessionId"] as? String, !sid.isEmpty else {
            throw APIError.requestFailed("no sessionId — server didn't echo for X-Lumen-Client. Body: \(bodyText.prefix(120))")
        }
        sessionId = sid
        // Cache the email so the PIN form can pre-fill it on next launch.
        UserDefaults.standard.set(email, forKey: "nexus.lastEmail")
        return sid
    }

    /// Identity-via-face. Sends a JPEG to /api/security/face/match. The
    /// server runs face-api.js, computes a 128-dim descriptor, matches
    /// against stored references for every active human, and on success
    /// returns a session id (echoed via X-Lumen-Client like the PIN flow).
    /// Same shape as the PIN authenticate() so callers can swap them.
    func authenticateWithFace(jpeg: Data) async throws -> String {
        guard let url = URL(string: "\(nexusBase)/api/security/face/match") else {
            throw APIError.invalidURL
        }
        let dataUrl = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1",                forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["imageDataUrl": dataUrl])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        let bodyJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        NSLog("[nexus-auth] POST /face/match -> %d body=%@", http.statusCode, bodyText.prefix(160) as CVarArg)

        if http.statusCode == 401 {
            let code = (bodyJSON?["error"] as? String) ?? "FACE_MISMATCH"
            throw APIError.requestFailed(code)
        }
        guard http.statusCode == 200 else {
            let msg = (bodyJSON?["error"] as? String) ?? "status \(http.statusCode)"
            throw APIError.requestFailed(msg)
        }
        // The server doesn't always echo sessionId for face/match, so fall
        // back to extracting nx_session from the Set-Cookie header. Both
        // paths land the cookie value in the same place.
        if let sid = bodyJSON?["sessionId"] as? String, !sid.isEmpty {
            sessionId = sid
            return sid
        }
        if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
            for chunk in setCookie.components(separatedBy: ", ") {
                let kv = chunk.components(separatedBy: ";").first ?? ""
                let parts = kv.components(separatedBy: "=")
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "nx_session" {
                    let sid = parts[1].trimmingCharacters(in: .whitespaces)
                    sessionId = sid
                    return sid
                }
            }
        }
        throw APIError.requestFailed("face match returned 200 but no session id was found")
    }

    /// Fetches the active human profile for the cached session. Used after
    /// authenticate() and on app launch to verify the cookie is still good.
    /// Returns nil on 401 (caller should drop the cached sessionId).
    func fetchActiveProfile() async -> ActiveProfile? {
        guard let sid = sessionId, !sid.isEmpty else { return nil }
        guard let url = URL(string: "\(nexusBase)/api/auth/me") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return ActiveProfile(
                humanId:     json["humanId"]     as? String ?? "",
                email:       json["email"]       as? String ?? "",
                displayName: json["displayName"] as? String ?? "",
                role:        json["role"]        as? String ?? "observer",
                isOwner:     json["isOwner"]     as? Bool   ?? false
            )
        } catch {
            return nil
        }
    }

    func logout() {
        sessionId = nil
    }

    // MARK: - Brain

    /// Sends a message to nexus-web Eve (Grok with full tool calling).
    /// Returns Eve's reply text. Conversation threading happens server-side
    /// keyed on `source: "ios"`.
    func askEve(message: String, conversationId: String? = nil) async throws -> (content: String, conversationId: String?, toolCalls: [ToolCallSummary]) {
        guard let sid = sessionId, !sid.isEmpty else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve") else { throw APIError.invalidURL }

        var body: [String: Any] = [
            "userMessage": message,
            "source":      "ios",
        ]
        if let conversationId { body["conversationId"] = conversationId }

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",      forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        if http.statusCode == 401 {
            sessionId = nil  // session expired — force re-auth on next try
            throw APIError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw APIError.requestFailed("status \(http.statusCode)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? String ?? ""
        let convId  = json?["conversationId"] as? String

        // Parse tool_calls trace — same JSON contract as Lumen + nexus-web,
        // so iOS gets visible Eve actions for free.
        var toolCalls: [ToolCallSummary] = []
        if let raw = json?["tool_calls"] as? [[String: Any]] {
            for tc in raw {
                let name   = (tc["name"]   as? String) ?? "unknown"
                let args   = (tc["args"]   as? [String: Any]) ?? [:]
                let result = (tc["result"] as? [String: Any]) ?? [:]
                toolCalls.append(.from(rawName: name, args: args, result: result))
            }
        }

        guard !content.isEmpty else { throw APIError.requestFailed("empty content") }
        return (content, convId, toolCalls)
    }

    /// Streaming variant of askEve — consumes Server-Sent Events from /api/eve
    /// and forwards content chunks via `onChunk`, tool calls via `onToolCall`,
    /// returning the final assembled (content, conversationId, toolCalls). The
    /// SSE event shape mirrors what Lumen Desktop consumes:
    ///   data: {"type": "meta",      "conversationId": "..."}
    ///   data: {"type": "delta",     "content": "..."}
    ///   data: {"type": "tool_call", "name": "...", "args": {...}, "result": {...}}
    ///   data: {"type": "done",      "content": "...", "conversationId": "..."}
    func askEveStreaming(
        message: String,
        conversationId: String? = nil,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCallSummary) -> Void
    ) async throws -> (content: String, conversationId: String?, toolCalls: [ToolCallSummary]) {
        guard let sid = sessionId, !sid.isEmpty else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve") else { throw APIError.invalidURL }

        var body: [String: Any] = [
            "userMessage": message,
            "source":      "ios",
            "stream":      true,
        ]
        if let conversationId { body["conversationId"] = conversationId }

        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(sid)",     forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        if http.statusCode == 401 { sessionId = nil; throw APIError.unauthorized }
        guard http.statusCode == 200 else {
            throw APIError.requestFailed("status \(http.statusCode)")
        }

        var full       = ""
        var newConvId: String? = nil
        var collected: [ToolCallSummary] = []

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data  = payload.data(using: .utf8),
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type  = json["type"] as? String
            else { continue }

            switch type {
            case "meta":
                newConvId = json["conversationId"] as? String
            case "delta":
                if let chunk = json["content"] as? String, !chunk.isEmpty {
                    full += chunk
                    await MainActor.run { onChunk(chunk) }
                }
            case "tool_call":
                let name   = (json["name"]   as? String) ?? "unknown"
                let args   = (json["args"]   as? [String: Any]) ?? [:]
                let result = (json["result"] as? [String: Any]) ?? [:]
                let summary = ToolCallSummary.from(rawName: name, args: args, result: result)
                collected.append(summary)
                await MainActor.run { onToolCall(summary) }
            case "done":
                if let final = json["content"]        as? String, !final.isEmpty { full = final }
                if let cid   = json["conversationId"] as? String { newConvId = cid }
            case "error":
                throw APIError.requestFailed("server-side stream error")
            default:
                break
            }
        }

        guard !full.isEmpty else { throw APIError.requestFailed("empty stream") }
        return (full, newConvId, collected)
    }

    // MARK: - Conversation history

    struct ConversationSummary: Decodable, Identifiable {
        let id: String
        let title: String
        let source: String
        let updated_at: String
    }

    struct HistoryMessage: Decodable, Identifiable {
        var id: String { "\(role)-\(created_at)" }
        let role: String
        let content: String
        let created_at: String
    }

    func fetchConversations() async throws -> [ConversationSummary] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/conversations") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.requestFailed("conversations") }
        struct Wrap: Decodable { let conversations: [ConversationSummary] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).conversations) ?? []
    }

    func fetchHistory(conversationId: String) async throws -> [HistoryMessage] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard var comps = URLComponents(string: "\(nexusBase)/api/eve/history") else { throw APIError.invalidURL }
        comps.queryItems = [URLQueryItem(name: "conversationId", value: conversationId)]
        guard let url = comps.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.requestFailed("history") }
        struct Wrap: Decodable { let messages: [HistoryMessage] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).messages) ?? []
    }

    // MARK: - Remote control: agents + operations

    struct AgentSummary: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let role: String?
        let status: String
        let total_findings: Int?
        let last_scanned_at: String?
    }

    struct OperationSummary: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let status: String
        let priority: String?
        let description: String?
        let updated_at: String?
    }

    /// Fetch all agents owned by the current user.
    func fetchAgents() async throws -> [AgentSummary] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/agents") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("agents \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        // /api/agents returns a bare array
        return (try? JSONDecoder().decode([AgentSummary].self, from: data)) ?? []
    }

    // MARK: - Briefing + Arena log

    struct BriefingStats: Decodable {
        let activeOps: Int
        let activeAgents: Int
        let activeDirectives: Int
        let memories: Int
    }
    struct BriefingOp: Decodable, Identifiable {
        let id: String
        let label: String
        let name: String?
        let status: String
        let priority: String?
        let createdAt: String?
        let updatedAt: String?
    }
    struct BriefingFinding: Decodable, Identifiable {
        var id: String { "\(agent)-\(createdAt)" }
        let agent: String
        let summary: String?
        let createdAt: String
    }
    struct BriefingFindings: Decodable {
        let totalCount: Int
        let perAgent: [String: Int]
        let latest: [BriefingFinding]
    }
    struct BriefingResearch: Decodable, Identifiable {
        let id: String
        let operationLabel: String
        let model: String?
        let summary: String
        let completedAt: String
    }
    struct BriefingDelta: Decodable {
        let newOperations: [BriefingOp]
        let statusChangedOperations: [BriefingOp]
        let findings: BriefingFindings
        let completedResearch: [BriefingResearch]
    }
    struct BriefingResponse: Decodable {
        let since: String
        let now: String
        let stats: BriefingStats
        let delta: BriefingDelta
    }

    /// Fetch the "what changed since X" briefing. Defaults to the last 24h.
    /// Powers the iOS briefing tab. Same shape as Lumen's EveBriefingView.
    func fetchBriefing(since: Date? = nil) async throws -> BriefingResponse {
        guard let sid = sessionId else { throw APIError.unauthorized }
        var components = URLComponents(string: "\(nexusBase)/api/eve/briefing")
        if let since {
            let iso = ISO8601DateFormatter()
            components?.queryItems = [URLQueryItem(name: "since", value: iso.string(from: since))]
        }
        guard let url = components?.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("briefing \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(BriefingResponse.self, from: data)
    }

    struct ArenaEntry: Decodable, Identifiable {
        let id: String
        let action: String
        let caller: String?
        let payload: AnyJSON?
        let result: AnyJSON?
        let status: String?
        let error_msg: String?
        let created_at: String
    }
    /// Loose JSON wrapper so payload/result columns survive decoding without
    /// us having to pre-declare every shape Eve might call. UI just renders
    /// the raw text where useful.
    struct AnyJSON: Decodable {
        let raw: String
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: AnyDecodable].self) {
                self.raw = (try? String(data: JSONEncoder().encode(dict.mapValues { $0.value }), encoding: .utf8)) ?? "{}"
            } else if let arr = try? container.decode([AnyDecodable].self) {
                self.raw = (try? String(data: JSONEncoder().encode(arr.map { $0.value }), encoding: .utf8)) ?? "[]"
            } else if let s = try? container.decode(String.self) {
                self.raw = s
            } else if let n = try? container.decode(Double.self) {
                self.raw = String(n)
            } else if let b = try? container.decode(Bool.self) {
                self.raw = String(b)
            } else {
                self.raw = ""
            }
        }
    }
    /// Erased decodable used only by AnyJSON to round-trip loose values.
    private struct AnyDecodable: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s }
            else if let n = try? c.decode(Double.self) { value = String(n) }
            else if let b = try? c.decode(Bool.self) { value = String(b) }
            else { value = "" }
        }
    }

    /// Fetch recent arena_action_log rows. The audit trail of every Arena
    /// call Eve has fired (task creates, payments, sync pushes). Empty
    /// caller/action means "everything"; otherwise filter server-side.
    func fetchArenaLog(limit: Int = 50, caller: String? = nil, action: String? = nil) async throws -> [ArenaEntry] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        var comps = URLComponents(string: "\(nexusBase)/api/arena/log")
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let caller { items.append(URLQueryItem(name: "caller", value: caller)) }
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        comps?.queryItems = items
        guard let url = comps?.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("arena/log \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        struct Wrap: Decodable { let entries: [ArenaEntry] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).entries) ?? []
    }

    /// Fetch all operations.
    func fetchOperations() async throws -> [OperationSummary] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("operations \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        struct Wrap: Decodable { let operations: [OperationSummary] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).operations) ?? []
    }

    /// Trigger a manual scan on the given agent. Server enforces that the
    /// agent be in active/deployed status.
    @discardableResult
    func runAgent(id: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/agents/run") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["agentId": id])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Toggle agent status between active and standby (or set explicitly).
    @discardableResult
    func setAgentStatus(id: String, status: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/agents") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "status": status])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Update operation status (planning / active / paused / complete / aborted).
    @discardableResult
    func setOperationStatus(id: String, status: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "status": status])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Operation detail (records + briefs)

    struct OperationRecord: Decodable, Identifiable {
        let id: String
        let type: String?
        let title: String?
        let content: String?
        let source: String?
        let priority: String?
        let created_at: String?
    }

    struct OperationBrief: Decodable, Identifiable {
        let id: String
        let kind: String
        let content: String
        let generated_at: String?
    }

    /// Records attached to an operation (notes, files, links, etc).
    func fetchOperationRecords(operationId: String) async throws -> [OperationRecord] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations/records?operation_id=\(operationId)")
        else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("op-records \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return (try? JSONDecoder().decode([OperationRecord].self, from: data)) ?? []
    }

    /// Eve-generated briefs for an operation, keyed by kind
    /// (summary / actions / contradictions / themes / next-steps).
    func fetchOperationBriefs(operationId: String) async throws -> [String: OperationBrief] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations/\(operationId)/briefs")
        else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("op-briefs \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return (try? JSONDecoder().decode([String: OperationBrief].self, from: data)) ?? [:]
    }

    // MARK: - Agent activity

    struct AgentActivity: Decodable, Identifiable {
        let id: String
        let action: String
        let details: AnyJSON?
        let created_at: String
    }

    /// Recent activity entries for one agent — scan history, status flips,
    /// findings. Powers the iOS agent detail screen.
    func fetchAgentActivity(agentId: String, limit: Int = 50) async throws -> [AgentActivity] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/agents/activity?agent_id=\(agentId)&limit=\(limit)")
        else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("agent-activity \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        struct Wrap: Decodable { let activity: [AgentActivity] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).activity) ?? []
    }

    // MARK: - Schedules

    struct ScheduleSummary: Decodable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let cron_expression: String
        let timezone: String?
        let target_type: String
        let target_id: String?
        let enabled: Bool
        let next_run_at: String?
        let last_run_at: String?
        let last_status: String?
        let last_error: String?
    }

    /// All schedules owned by the current user, newest first.
    func fetchSchedules() async throws -> [ScheduleSummary] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/schedules") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("schedules \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        struct Wrap: Decodable { let schedules: [ScheduleSummary] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).schedules) ?? []
    }

    // MARK: - Terminal bridge (Phase 2)

    struct TerminalSession: Decodable, Identifiable, Hashable {
        let id: String
        let mac_label: String?
        let folder: String
        let claude_path: String?
        let title: String?
        let status: String              // running | exited | error | stale
        let exit_code: Int?
        let last_snapshot: String?
        let last_snapshot_at: String?
        let last_heartbeat_at: String?
        let started_at: String?
        let ended_at: String?
    }

    /// Sessions Lumen has registered for the active human, newest first.
    /// Status 'stale' is computed server-side from heartbeat freshness —
    /// the iOS app just renders what it gets.
    func fetchTerminalSessions() async throws -> [TerminalSession] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/terminal/sessions") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed("terminal/sessions \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        struct Wrap: Decodable { let sessions: [TerminalSession] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).sessions) ?? []
    }

    /// Single-session read — viewer uses this to refresh snapshot text
    /// while the detail screen is open without re-listing every session.
    func fetchTerminalSession(id: String) async throws -> TerminalSession? {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/terminal/sessions/\(id)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(TerminalSession.self, from: data)
    }

    /// Queue a command to be fed into the Mac-side PTY. Lumen polls the
    /// command queue every few seconds and dispatches each via
    /// SwiftTerm.send. Caller decides whether to include trailing \n —
    /// pass "ls\n" to actually execute, or "ls" to just type the chars.
    @discardableResult
    func submitTerminalCommand(sessionId: String, command: String) async throws -> Bool {
        guard let sid = self.sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/terminal/commands") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "session_id": sessionId,
            "command":    command,
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 201
    }

    /// Direct-to-Ollama path. Skips nexus-web entirely — the iOS app POSTs
    /// straight to the home Mac's Ollama daemon. Sub-second on home wifi.
    /// `localBrainURL` must be set in Settings (see UserDefaults key).
    /// No conversation threading or memory-bank context — single-shot only.
    func askLocalDirect(message: String, history: [String] = []) async throws -> String {
        guard let urlString = localBrainURL, let url = URL(string: urlString) else {
            throw APIError.requestFailed("local brain URL not configured")
        }

        let systemPrompt = "You are Eve, the private AI command intelligence of Patrick Maxwell. Address Patrick as \"sir\" or \"Director.\" Be direct, sharp, efficient. Dry wit permitted. Keep responses short — you are speaking aloud, not writing a report."

        var msgs: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for h in history.suffix(8) { msgs.append(["role": "user", "content": h]) }
        msgs.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "model":       localBrainModel,
            "messages":    msgs,
            "temperature": 0.7,
            "max_tokens":  600,
        ]

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        guard http.statusCode == 200 else { throw APIError.requestFailed("status \(http.statusCode)") }
        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !content.isEmpty else { throw APIError.requestFailed("empty content") }
        return content
    }

    /// Lists models available on the home Mac's Ollama daemon. Returns
    /// model names like "llama3.2:3b". Empty array means the LAN brain is
    /// unreachable (or no models installed). Used by Settings to populate
    /// the local-brain model picker.
    func listLocalModels() async -> [String] {
        guard let raw = localBrainURL,
              let host = URL(string: raw)?.host,
              let scheme = URL(string: raw)?.scheme,
              let url = URL(string: "\(scheme)://\(host):11434/api/tags")
        else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// Asks Eve's local Ollama to title a conversation in 3-5 words. Used
    /// after the first user/assistant exchange to label the conversation in
    /// the history sidebar. Best-effort — returns nil if the LAN brain is
    /// unreachable so callers can fall back to "Untitled".
    func generateTitle(messages: [(role: String, content: String)]) async -> String? {
        guard let raw = localBrainURL,
              let host = URL(string: raw)?.host,
              let scheme = URL(string: raw)?.scheme,
              let url = URL(string: "\(scheme)://\(host):11434/v1/chat/completions")
        else { return nil }

        var msgs: [[String: String]] = [[
            "role":    "system",
            "content": "Generate a 3-5 word title for this conversation. Reply with only the title, no quotes, no punctuation.",
        ]]
        for m in messages.suffix(6) { msgs.append(["role": m.role, "content": m.content]) }

        let body: [String: Any] = [
            "model":       localBrainModel,
            "messages":    msgs,
            "temperature": 0.3,
            "max_tokens":  20,
        ]

        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let title = (choices.first?["message"] as? [String: Any])?["content"] as? String
        else { return nil }

        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Vision variant — sends base64 images to /api/eve/local. Server
    /// auto-routes to llava when images are present.
    func askEveLocalWithImages(message: String, images: [String], conversationId: String? = nil) async throws -> (content: String, conversationId: String?) {
        guard let sid = sessionId, !sid.isEmpty else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/local") else { throw APIError.invalidURL }

        var body: [String: Any] = [
            "userMessage": message.isEmpty ? "What do you see, Eve?" : message,
            "source":      "ios",
            "images":      images,
        ]
        if let conversationId { body["conversationId"] = conversationId }

        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        if http.statusCode == 401 { sessionId = nil; throw APIError.unauthorized }
        guard http.statusCode == 200 else { throw APIError.requestFailed("status \(http.statusCode)") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? String ?? ""
        let convId  = json?["conversationId"] as? String
        guard !content.isEmpty else { throw APIError.requestFailed("empty content") }
        return (content, convId)
    }

    /// Local-brain variant — hits /api/eve/local (Ollama) instead of Grok.
    /// Cheaper, fully offline if pointed at home LAN, but no tool calling.
    func askEveLocal(message: String, conversationId: String? = nil, model: String? = nil) async throws -> (content: String, conversationId: String?) {
        guard let sid = sessionId, !sid.isEmpty else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/local") else { throw APIError.invalidURL }

        var body: [String: Any] = [
            "userMessage": message,
            "source":      "ios",
        ]
        if let conversationId { body["conversationId"] = conversationId }
        if let model { body["model"] = model }

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        if http.statusCode == 401 {
            sessionId = nil
            throw APIError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw APIError.requestFailed("status \(http.statusCode)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? String ?? ""
        let convId  = json?["conversationId"] as? String
        guard !content.isEmpty else { throw APIError.requestFailed("empty content") }
        return (content, convId)
    }

    // MARK: - Schedules (toggle + run-now)

    /// Toggle a schedule's enabled flag. Backed by PATCH /api/schedules/[id].
    @discardableResult
    func setScheduleEnabled(id: String, enabled: Bool) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/schedules/\(id)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Fire a schedule immediately, bypassing its cron — POST /api/schedules/[id]/run.
    @discardableResult
    func runScheduleNow(id: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/schedules/\(id)/run") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Operation records (create)

    /// Append a record to an operation — POST /api/operations/records.
    /// `type` is one of: intel | finding | data | alert | note (server defaults to "note").
    @discardableResult
    func addOperationRecord(
        operationId: String,
        title: String,
        content: String,
        type: String = "note",
        priority: String = "normal"
    ) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations/records") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "operation_id": operationId,
            "title": title,
            "content": content,
            "type": type,
            "priority": priority,
            "source": "ios",
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Create operations / agents

    /// POST /api/operations — create a new operation. Returns the new id.
    @discardableResult
    func createOperation(
        name: String,
        description: String = "",
        objectives: String = "",
        priority: String = "medium",
        status: String = "planning"
    ) async throws -> String? {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": description,
            "objectives": objectives,
            "priority": priority,
            "status": status,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed("create-operation")
        }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return parsed?["id"] as? String
    }

    /// POST /api/agents — create a new agent. `capabilities` is a free-form
    /// list of short labels (e.g. ["research", "writing"]). Returns the id.
    @discardableResult
    func createAgent(
        name: String,
        role: String,
        personality: String = "",
        capabilities: [String] = [],
        directives: String = "",
        status: String = "standby"
    ) async throws -> String? {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/agents") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "role": role,
            "personality": personality,
            "capabilities": capabilities,
            "directives": directives,
            "status": status,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed("create-agent")
        }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return parsed?["id"] as? String
    }

    /// POST /api/schedules — create a new cron schedule. The web side
    /// validates the cron expression and computes the first `next_run_at`,
    /// so we don't have to parse on device.
    @discardableResult
    func createSchedule(
        name: String,
        cronExpression: String,
        targetType: String,
        targetId: String? = nil,
        timezone: String = "America/Chicago",
        payload: [String: Any] = [:],
        enabled: Bool = true,
        description: String? = nil
    ) async throws -> String? {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/schedules") else { throw APIError.invalidURL }
        var body: [String: Any] = [
            "name": name,
            "cron_expression": cronExpression,
            "timezone": timezone,
            "target_type": targetType,
            "payload": payload,
            "enabled": enabled,
        ]
        if let targetId, !targetId.isEmpty { body["target_id"] = targetId }
        if let description, !description.isEmpty { body["description"] = description }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Server returns 400 with { error: "..." } on validation failure;
            // surface that message instead of a generic "create-schedule".
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (json?["error"] as? String) ?? "create-schedule status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw APIError.requestFailed(msg)
        }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return parsed?["id"] as? String
    }

    // MARK: - Cross-thread search

    struct ConversationSearchHit: Decodable, Identifiable {
        let conversation_id: String
        let title: String
        let source: String
        let snippet: String
        let matchType: String
        let role: String?
        let created_at: String?
        let updated_at: String?
        var id: String { conversation_id }
    }

    /// GET /api/eve/search?q=… — matches conversation titles AND message
    /// content. Returns one hit per conversation with an excerpt snippet.
    /// Empty/short queries (<2 chars) return [].
    func searchConversations(q: String) async throws -> [ConversationSearchHit] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              var comps = URLComponents(string: "\(nexusBase)/api/eve/search")
        else { return [] }
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed("search")
        }
        struct Wrap: Decodable { let results: [ConversationSearchHit] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).results) ?? []
    }

    // MARK: - Eve Memory bank

    struct EveMemory: Decodable, Identifiable {
        let id: String
        let type: String          // fact | preference | event | reference | etc.
        let content: String
        let priority: Int
        let source: String?
        let created_at: String?
        let updated_at: String?
    }

    /// GET /api/eve/memory — fetch Eve's active memory bank.
    func fetchMemories() async throws -> [EveMemory] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/memory") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.requestFailed("memories") }
        struct Wrap: Decodable { let memories: [EveMemory] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).memories) ?? []
    }

    @discardableResult
    func addMemory(type: String, content: String, priority: Int = 5) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/memory") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": type,
            "content": content,
            "priority": priority,
            "source": "ios",
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// DELETE deactivates (sets is_active=false) — server keeps the row.
    @discardableResult
    func deleteMemory(id: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/memory") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Eve Directives

    struct EveDirective: Decodable, Identifiable {
        let id: String
        let type: String          // directive | protocol
        let title: String
        let content: String
        let priority: Int
        let target: String?
        let is_active: Bool
        let created_at: String?
        let updated_at: String?
    }

    /// GET /api/eve/directives — fetch the Director-defined directives and
    /// protocols that override Eve's defaults.
    func fetchDirectives() async throws -> [EveDirective] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/directives") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.requestFailed("directives") }
        struct Wrap: Decodable { let directives: [EveDirective] }
        return (try? JSONDecoder().decode(Wrap.self, from: data).directives) ?? []
    }

    @discardableResult
    func addDirective(type: String, title: String, content: String, priority: Int = 0, target: String = "all") async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/directives") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": type, "title": title, "content": content, "priority": priority, "target": target,
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    @discardableResult
    func setDirectiveActive(id: String, isActive: Bool) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/directives") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "is_active": isActive])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    @discardableResult
    func deleteDirective(id: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/eve/directives") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// PATCH /api/operations — update arbitrary fields on an existing
    /// operation. Send only the fields you want changed (id is required;
    /// everything else is optional, server merges). On 200 returns the
    /// full row but for the iOS flow we just need pass/fail.
    @discardableResult
    func updateOperation(
        id: String,
        name: String? = nil,
        description: String? = nil,
        objectives: String? = nil,
        priority: String? = nil,
        status: String? = nil
    ) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations") else { throw APIError.invalidURL }
        var body: [String: Any] = ["id": id]
        if let name        { body["name"] = name }
        if let description { body["description"] = description }
        if let objectives  { body["objectives"] = objectives }
        if let priority    { body["priority"] = priority }
        if let status      { body["status"] = status }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// PATCH /api/agents — update arbitrary fields on an existing agent.
    /// Same semantics as updateOperation.
    @discardableResult
    func updateAgent(
        id: String,
        name: String? = nil,
        role: String? = nil,
        personality: String? = nil,
        capabilities: [String]? = nil,
        directives: String? = nil,
        status: String? = nil
    ) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/agents") else { throw APIError.invalidURL }
        var body: [String: Any] = ["id": id]
        if let name         { body["name"] = name }
        if let role         { body["role"] = role }
        if let personality  { body["personality"] = personality }
        if let capabilities { body["capabilities"] = capabilities }
        if let directives   { body["directives"] = directives }
        if let status       { body["status"] = status }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// POST /api/operations/[id]/briefs — ask Eve to generate a brief of
    /// a specific kind. Server returns the new `OperationBrief` row;
    /// surface the failure reason if Eve refuses (e.g. no records yet).
    @discardableResult
    func generateBrief(operationId: String, kind: String) async throws -> OperationBrief? {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations/\(operationId)/briefs")
        else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 90)  // analyst call — slow
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["kind": kind])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (json?["error"] as? String) ?? "generate-brief status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw APIError.requestFailed(msg)
        }
        return try? JSONDecoder().decode(OperationBrief.self, from: data)
    }

    /// POST /api/operations/records/[id]/research — kick off a research job
    /// against an existing record. Eve will dispatch the configured research
    /// brain to produce child findings. Returns true on accept.
    @discardableResult
    func runRecordResearch(recordId: String) async throws -> Bool {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/operations/records/\(recordId)/research")
        else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (200...299).contains(code)
    }

    // MARK: - Arena connections

    struct ArenaConnection: Decodable, Identifiable {
        let provider: String
        let label: String?
        let status: String
        let last_used_at: String?
        let last_error: String?
        var id: String { "\(provider)-\(label ?? "")" }
    }

    /// User's connected providers (ClickUp, Notion, GitHub, etc.). Used for
    /// the Connections screen — read-only visibility, no auth flow on device.
    func fetchConnections() async throws -> [ArenaConnection] {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/arena/connections") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed("connections")
        }
        struct Wrap: Decodable { let connections: [ArenaConnection] }
        if let wrap = try? JSONDecoder().decode(Wrap.self, from: data) {
            return wrap.connections
        }
        return (try? JSONDecoder().decode([ArenaConnection].self, from: data)) ?? []
    }

    // MARK: - Nexus Map

    struct MapNode: Decodable, Identifiable {
        let id: String
        let type: String        // conversation | agent | operation | topic | record | research | directive | human
        let title: String
        let subtitle: String
        let preview: String
        let tags: [String]
        let status: String?
        let priority: String?
        let messageCount: Int
        let createdAt: String
        let updatedAt: String
    }

    struct MapEdge: Decodable, Hashable {
        let source: String
        let target: String
        let type: String         // topic-link | temporal | record-belongs-to | …
    }

    struct MapResponse: Decodable {
        let nodes: [MapNode]
        let edges: [MapEdge]?
        let activeResearch: Int?
    }

    /// Pull the entire Nexus Map graph (all entity types). The web/Lumen
    /// surface renders this as a force-directed graph; on iPhone we group
    /// by node `type` and let the user browse counts + drill in.
    func fetchNexusMap() async throws -> MapResponse {
        guard let sid = sessionId else { throw APIError.unauthorized }
        guard let url = URL(string: "\(nexusBase)/api/nexus-map") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.requestFailed("nexus-map")
        }
        return try JSONDecoder().decode(MapResponse.self, from: data)
    }
}
