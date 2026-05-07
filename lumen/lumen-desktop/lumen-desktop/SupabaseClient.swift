import Foundation

// Direct Supabase REST client — bypasses nexus-web entirely.
// Trusted local app: service role key is acceptable here.
class SupabaseClient {
    static let shared = SupabaseClient()

    private let baseURL  = "https://rtkzvsqulliaoizutsqz.supabase.co"
    private let apiKey   = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0a3p2c3F1bGxpYW9penV0c3F6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTYxNzM0MSwiZXhwIjoyMDkxMTkzMzQxfQ.OMRaTWkHQe_9RufUU6MloYAwdw9kPmIPAraKDINioBs"
    private let userID   = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

    private var rest: String { "\(baseURL)/rest/v1" }

    private func headers(prefer: String? = nil) -> [String: String] {
        var h = [
            "apikey":        apiKey,
            "Authorization": "Bearer \(apiKey)",
            "Content-Type":  "application/json",
        ]
        if let p = prefer { h["Prefer"] = p }
        return h
    }

    // MARK: - Conversations

    /// Create a conversation. When `explicitId` is passed (the optimistic-
    /// write path), Postgres uses it as the primary key — same id flows
    /// through cache, UI, and server, no swap required.
    func createConversation(title: String, source: String = "lumen", explicitId: String? = nil) async -> String? {
        guard let url = URL(string: "\(rest)/eve_conversations") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = headers(prefer: "return=representation")
        var payload: [String: Any] = [
            "user_id": userID,
            "title":   title,
            "source":  source,
        ]
        if let explicitId { payload["id"] = explicitId }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id   = arr.first?["id"] as? String else { return nil }
        return id
    }

    func updateConversationTitle(id: String, title: String) async {
        guard let url = URL(string: "\(rest)/eve_conversations?id=eq.\(id)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "PATCH"
        req.allHTTPHeaderFields = headers()
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title])
        _ = try? await URLSession.shared.data(for: req)
    }

    func touchConversation(id: String) async {
        let ts = ISO8601DateFormatter().string(from: Date())
        guard let url = URL(string: "\(rest)/eve_conversations?id=eq.\(id)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "PATCH"
        req.allHTTPHeaderFields = headers()
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["updated_at": ts])
        _ = try? await URLSession.shared.data(for: req)
    }

    func fetchConversations() async -> [ConversationSummary] {
        guard let url = URL(string:
            "\(rest)/eve_conversations?user_id=eq.\(userID)&select=id,title,source,updated_at&order=updated_at.desc&limit=60"
        ) else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.allHTTPHeaderFields = headers()
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        return arr.compactMap { d in
            guard let id    = d["id"]         as? String,
                  let title = d["title"]      as? String,
                  let upd   = d["updated_at"] as? String else { return nil }
            let date = isoFull.date(from: upd) ?? isoBasic.date(from: upd) ?? Date.distantPast
            return ConversationSummary(id: id, title: title,
                                       source: d["source"] as? String ?? "lumen",
                                       updatedAt: date)
        }
    }

    // MARK: - Messages

    func saveMessage(conversationId: String, role: String, content: String) async {
        guard let url = URL(string: "\(rest)/eve_history") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = headers()
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "user_id":         userID,
            "conversation_id": conversationId,
            "role":            role,
            "content":         content,
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    func fetchMessages(conversationId: String) async -> [ChatMessage] {
        guard let url = URL(string:
            "\(rest)/eve_history?conversation_id=eq.\(conversationId)&user_id=eq.\(userID)&select=role,content&order=created_at.asc&limit=200"
        ) else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.allHTTPHeaderFields = headers()
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let role    = d["role"]    as? String,
                  let content = d["content"] as? String else { return nil }
            return ChatMessage(role: role == "user" ? .user : .assistant, content: content)
        }
    }

    // MARK: - Memory context

    func fetchMemoryContext() async -> String {
        guard let url = URL(string:
            "\(rest)/eve_memory?user_id=eq.\(userID)&select=key,value&order=created_at.desc&limit=30"
        ) else { return "" }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.allHTTPHeaderFields = headers()
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return "" }
        let lines = arr.compactMap { d -> String? in
            guard let k = d["key"] as? String, let v = d["value"] as? String else { return nil }
            return "\(k): \(v)"
        }
        return lines.isEmpty ? "" : "\n\nMEMORY:\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Local session cache

extension SupabaseClient {
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lumen", isDirectory: true)
            .appendingPathComponent("session_cache.json")
    }

    func cacheSession(conversationId: String, messages: [ChatMessage]) {
        guard let url = SupabaseClient.cacheURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [[String: String]] = messages.map { [
            "role":    $0.role == .user ? "user" : "assistant",
            "content": $0.content,
        ]}
        let obj: [String: Any] = ["conversationId": conversationId, "messages": payload]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadCachedSession() -> (conversationId: String, messages: [ChatMessage])? {
        guard let url = SupabaseClient.cacheURL,
              let data = try? Data(contentsOf: url),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id   = obj["conversationId"] as? String,
              let arr  = obj["messages"]       as? [[String: String]] else { return nil }
        let messages = arr.compactMap { d -> ChatMessage? in
            guard let role    = d["role"],
                  let content = d["content"] else { return nil }
            return ChatMessage(role: role == "user" ? .user : .assistant, content: content)
        }
        return (id, messages)
    }
}
