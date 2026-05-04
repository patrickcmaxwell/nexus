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

    static let publicBase = "https://nexus.talkcircles.io"

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

    private static let sessionKey = "nexus.sessionId"
    var sessionId: String? {
        get { UserDefaults.standard.string(forKey: Self.sessionKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: Self.sessionKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.sessionKey) }
        }
    }

    enum APIError: Error { case invalidURL, unauthorized, requestFailed(String) }

    // MARK: - Auth

    /// Submits the 4-digit PIN, returns a session id on success and caches it.
    func authenticate(pin: String) async throws -> String {
        guard let url = URL(string: "\(nexusBase)/api/security/pin") else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1",                forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["pin": pin, "remember": true])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed("no http") }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard http.statusCode == 200 else {
            throw APIError.requestFailed("status \(http.statusCode)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let sid = json?["sessionId"] as? String, !sid.isEmpty else {
            throw APIError.requestFailed("no sessionId in response")
        }
        sessionId = sid
        return sid
    }

    func logout() { sessionId = nil }

    // MARK: - Brain

    /// Sends a message to nexus-web Eve (Grok with full tool calling).
    /// Returns Eve's reply text. Conversation threading happens server-side
    /// keyed on `source: "ios"`.
    func askEve(message: String, conversationId: String? = nil) async throws -> (content: String, conversationId: String?) {
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
        guard !content.isEmpty else { throw APIError.requestFailed("empty content") }
        return (content, convId)
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

    struct AgentSummary: Decodable, Identifiable {
        let id: String
        let name: String
        let role: String?
        let status: String
        let total_findings: Int?
        let last_scanned_at: String?
    }

    struct OperationSummary: Decodable, Identifiable {
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
}
