import Foundation

class LumenAPIManager {
    static let shared = LumenAPIManager()

    static let localBase  = "http://localhost:3000"
    static let remoteBase = "https://nexus.talkcircles.io"

    var nexusBase = localBase
    var sessionCookie: String?  // kept for nexus-web dashboard calls only

    private let lmStudioURL = "http://localhost:1234/v1/chat/completions"
    private let model       = "qwen3.5"

    // Loaded from Supabase at startup; enriches Eve's responses
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
        memoryContext = await SupabaseClient.shared.fetchMemoryContext()
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

    // MARK: - Chat (always LM Studio)

    func chat(message: String, history: ArraySlice<ChatMessage>) async throws -> String {
        guard let url = URL(string: lmStudioURL) else { throw APIError.invalidURL }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for msg in history.suffix(12) {
            messages.append(["role": msg.role == .user ? "user" : "assistant", "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        let body: [String: Any] = [
            "model":       model,
            "messages":    messages,
            "temperature": 0.7,
            "max_tokens":  600,
        ]

        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        return (choices?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
    }

    enum APIError: Error {
        case invalidURL, requestFailed
    }
}
