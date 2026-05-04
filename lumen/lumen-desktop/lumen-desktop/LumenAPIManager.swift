import Foundation

class LumenAPIManager {
    static let shared = LumenAPIManager()

    static let localBase  = "http://localhost:3000"
    static let remoteBase = "https://nexus.talkcircles.io"

    var nexusBase = localBase
    var sessionCookie: String?  // kept for nexus-web dashboard calls only

    // Local LLM (offline brain). Ollama exposes an OpenAI-compatible API
    // on :11434/v1 — same wire format LM Studio used, so the URL + model
    // name are the only knobs.
    private let localLLMURL  = "http://localhost:11434/v1/chat/completions"
    private let localTagsURL = "http://localhost:11434/api/tags"
    private static let localModelKey = "lumen.localModel"
    private static let defaultLocalModel = "llama3.2:3b"
    // Mutable + persisted via UserDefaults so the settings picker survives restart.
    var localModel: String = UserDefaults.standard.string(forKey: localModelKey) ?? defaultLocalModel

    // Eve's ElevenLabs voice. Default is "Bella" (free-tier allowed).
    // Common alternatives: "21m00Tcm4TlvDq8ikWAM" Rachel, "AZnzlk1XvdvUeBnXmlld" Domi,
    // "ErXwobaYiN019PkySvjV" Antoni, "MF3mGyEYCl7XYWbV9V6O" Elli.
    private static let voiceIdKey = "lumen.voiceId"
    private static let defaultVoiceId = "EXAVITQu4vr4xnSDxMaL"  // Bella
    var voiceId: String = UserDefaults.standard.string(forKey: voiceIdKey) ?? defaultVoiceId

    func setVoiceId(_ id: String) {
        voiceId = id
        UserDefaults.standard.set(id, forKey: LumenAPIManager.voiceIdKey)
    }

    // Loaded at startup; local files + Supabase memory appended to core prompt
    private var memoryContext = ""

    private let coreSystemPrompt = """
    You are Eve. You are the private AI command intelligence of Patrick Maxwell, \
    operating inside the Nexus command platform. You are not a general assistant. \
    You are Eve. Address Patrick as "sir" or "Director." Be direct, sharp, and \
    efficient. Dry wit is permitted. Do not over-explain. Keep responses concise — \
    you are speaking aloud, not writing a report. Short sentences, natural speech rhythm.
    """

    private var systemPrompt: String { coreSystemPrompt + memoryContext }

    // MARK: - Startup

    func loadMemoryContext() async {
        // Local markdown files take priority; Supabase memory appended after.
        // Place eve-base.md / eve-private.md in ~/Library/Application Support/Lumen/
        // to enable offline-first context without rebuilding the app.
        let base    = loadLocalMemoryFile(named: "eve-base")
        let private_ = loadLocalMemoryFile(named: "eve-private")
        let local   = [base, private_].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let remote  = await SupabaseClient.shared.fetchMemoryContext()
        memoryContext = (local.isEmpty ? "" : "\n\n\(local)") + remote
    }

    private func loadLocalMemoryFile(named name: String) -> String {
        // Try bundle first (added as a Copy Bundle Resource in Xcode)
        if let url = Bundle.main.url(forResource: name, withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // Fall back to ~/Library/Application Support/Lumen/<name>.md
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let url = support?.appendingPathComponent("Lumen/\(name).md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return ""
    }

    // MARK: - Base URL (for dashboard calls only)

    @discardableResult
    func resolveBaseURL() async -> String {
        if let url = URL(string: "\(LumenAPIManager.localBase)/api/dashboard/overview") {
            var req = URLRequest(url: url, timeoutInterval: 2)
            req.httpMethod = "GET"
            if (try? await URLSession.shared.data(for: req)) != nil {
                nexusBase = LumenAPIManager.localBase
                return nexusBase
            }
        }
        nexusBase = LumenAPIManager.remoteBase
        return nexusBase
    }

    private let anthropicApiKey = "PASTE_YOUR_KEY_HERE"

    // MARK: - Nexus-web Eve (preferred path)

    func callNexusEve(message: String, conversationId: String?, history: ArraySlice<ChatMessage>) async throws -> (content: String, conversationId: String?) {
        guard let cookie = sessionCookie, !cookie.isEmpty else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(nexusBase)/api/eve") else { throw APIError.invalidURL }

        let body: [String: Any] = [
            "userMessage":    message,
            "conversationId": conversationId as Any,
            "source":         "lumen",
        ]
        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        let json       = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content    = json?["content"]        as? String ?? ""
        let newConvId  = json?["conversationId"] as? String
        guard !content.isEmpty else { throw APIError.requestFailed }
        return (content, newConvId)
    }

    // MARK: - Chat (local Ollama → Claude fallback)

    func chat(message: String, history: ArraySlice<ChatMessage>) async throws -> String {
        do {
            return try await callLocalLLM(message: message, history: history)
        } catch {
            return try await callClaude(message: message, history: history)
        }
    }

    private func callLocalLLM(message: String, history: ArraySlice<ChatMessage>) async throws -> String {
        guard let url = URL(string: localLLMURL) else { throw APIError.invalidURL }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for msg in history.suffix(12) {
            messages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "model":       localModel,
            "messages":    messages,
            "temperature": 0.7,
            "max_tokens":  600,
        ]

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        guard !content.isEmpty else { throw APIError.requestFailed }
        return content
    }

    // MARK: - Local model discovery / selection

    /// Chat with a specific agent's persona via /api/agents/chat. Returns
    /// the agent's reply. The agent uses its own role/personality/directives
    /// as the system prompt, so each agent feels distinct.
    func chatWithAgent(agentId: String, message: String, history: [(role: String, content: String)]) async throws -> String {
        guard let cookie = sessionCookie, !cookie.isEmpty else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(nexusBase)/api/agents/chat") else { throw APIError.invalidURL }
        let historyPayload = history.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "agentId": agentId,
            "message": message,
            "history": historyPayload,
        ]
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)",  forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.requestFailed }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["response"] as? String ?? ""
        guard !content.isEmpty else { throw APIError.requestFailed }
        return content
    }

    /// Sends a message + base64 images to nexus-web /api/eve/local, which
    /// auto-routes to llava:7b for vision when images are present.
    /// Returns Eve's reply text (memory bank + threading handled server-side).
    func callLocalEveWithImages(message: String, images: [String], conversationId: String?) async throws -> (content: String, conversationId: String?) {
        guard let cookie = sessionCookie, !cookie.isEmpty else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(nexusBase)/api/eve/local") else { throw APIError.invalidURL }

        var body: [String: Any] = [
            "userMessage": message,
            "source":      "lumen",
            "images":      images,
        ]
        if let conversationId { body["conversationId"] = conversationId }

        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)",  forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.requestFailed }
        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? String ?? ""
        let convId  = json?["conversationId"] as? String
        guard !content.isEmpty else { throw APIError.requestFailed }
        return (content, convId)
    }

    /// Lists all models pulled into the local Ollama daemon. Returns model
    /// names like "llama3.2:3b". Empty array means Ollama is offline or has
    /// no models installed.
    func listLocalModels() async -> [String] {
        guard let url = URL(string: localTagsURL) else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// Switch the active local model at runtime. Persists across launches.
    /// The next callLocalLLM / generateTitle call will use this model.
    /// Pull new models via `ollama pull <name>` from the terminal first.
    func setLocalModel(_ name: String) {
        localModel = name
        UserDefaults.standard.set(name, forKey: LumenAPIManager.localModelKey)
    }

    /// Streaming variant of callLocalLLM. The handler is invoked once per
    /// token chunk as Ollama emits it; final accumulated text is returned
    /// when the stream completes. Use this in voice/UI flows where you want
    /// progressive rendering instead of a single 5–10s wait.
    func callLocalLLMStreaming(
        message: String,
        history: ArraySlice<ChatMessage>,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: localLLMURL) else { throw APIError.invalidURL }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for msg in history.suffix(12) {
            messages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "model":       localModel,
            "messages":    messages,
            "temperature": 0.7,
            "max_tokens":  600,
            "stream":      true,
        ]

        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        var full = ""
        for try await line in bytes.lines {
            // Ollama's OpenAI-compatible stream emits SSE lines: `data: {...}` or `data: [DONE]`
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data  = payload.data(using: .utf8),
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = (choices.first?["delta"] as? [String: Any])?["content"] as? String,
                  !delta.isEmpty
            else { continue }
            full += delta
            await MainActor.run { onChunk(delta) }
        }
        guard !full.isEmpty else { throw APIError.requestFailed }
        return full
    }

    private func callClaude(message: String, history: ArraySlice<ChatMessage>) async throws -> String {
        let apiKey = anthropicApiKey
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw APIError.invalidURL
        }

        var messages: [[String: String]] = []
        for msg in history.suffix(12) {
            messages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 600,
            "system":     systemPrompt,
            "messages":   messages,
        ]

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,              forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        return (content?.first?["text"] as? String) ?? ""
    }

    // MARK: - Agent / Operation actions

    func runAgent(id: String) async {
        guard let cookie = sessionCookie, !cookie.isEmpty else { return }
        guard let url = URL(string: "\(nexusBase)/api/agents/run") else { return }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["agentId": id])
        _ = try? await URLSession.shared.data(for: req)
    }

    func setAgentStatus(id: String, status: String) async {
        guard let cookie = sessionCookie, !cookie.isEmpty else { return }
        guard let url = URL(string: "\(nexusBase)/api/agents") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "status": status])
        _ = try? await URLSession.shared.data(for: req)
    }

    func setOpStatus(id: String, status: String) async {
        guard let cookie = sessionCookie, !cookie.isEmpty else { return }
        guard let url = URL(string: "\(nexusBase)/api/operations") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "status": status])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Title generation

    func generateTitle(history: [ChatMessage]) async -> String? {
        guard let url = URL(string: localLLMURL) else { return nil }

        var messages: [[String: String]] = [[
            "role": "system",
            "content": "Generate a 3-5 word title for this conversation. Reply with only the title, no quotes, no punctuation.",
        ]]
        for msg in history.suffix(6) {
            messages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.content])
        }

        let body: [String: Any] = [
            "model":       localModel,
            "messages":    messages,
            "temperature": 0.3,
            "max_tokens":  20,
        ]

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let title = (choices.first?["message"] as? [String: Any])?["content"] as? String
        else { return nil }

        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    enum APIError: Error {
        case invalidURL, requestFailed, noAPIKey
    }
}
