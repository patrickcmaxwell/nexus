import SwiftUI
import Combine

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    enum Role { case user, assistant }
}

struct AgentStatus: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let status: String
    let lastAction: String
}

struct OperationItem: Identifiable {
    let id = UUID()
    let codename: String
    let name: String
    let status: String
    let priority: String
}

struct ConversationSummary: Identifiable {
    let id: String
    let title: String
    let source: String
    let updatedAt: Date
}

enum ActivePanel: Equatable {
    case none, agents, operations, chats
}

enum EveStatus: Equatable {
    case idle, listening, thinking, speaking

    var label: String {
        switch self {
        case .idle:      return "STANDBY"
        case .listening: return "LISTENING"
        case .thinking:  return "PROCESSING"
        case .speaking:  return "SPEAKING"
        }
    }

    var color: Color {
        switch self {
        case .idle:      return Color.white.opacity(0.2)
        case .listening: return Color(red: 0.2, green: 0.9, blue: 0.4)
        case .thinking:  return Color(red: 1.0, green: 0.8, blue: 0.0)
        case .speaking:  return Color(red: 0.0, green: 0.78, blue: 1.0)
        }
    }
}

// MARK: - Store

@MainActor
class LumenStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var eveStatus: EveStatus = .idle
    @Published var activePanel: ActivePanel = .none
    @Published var audioLevel: Float = 0
    @Published var partialTranscript: String = ""
    @Published var lastError: String? = nil
    @Published var fluidListening: Bool = false

    @Published var agents: [AgentStatus] = []
    @Published var operations: [OperationItem] = []
    @Published var conversations: [ConversationSummary] = []
    @Published var loadedHistory: [ChatMessage] = []
    @Published var loadedHistoryTitle: String? = nil

    // ID of the active conversation thread
    private(set) var currentConversationId: String? {
        get { UserDefaults.standard.string(forKey: "lumen.currentConversationId") }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.currentConversationId") }
    }

    let voice: EveVoiceManager
    let api: LumenAPIManager

    init() {
        self.api   = LumenAPIManager.shared
        self.voice = EveVoiceManager()

        voice.onTranscriptFinal = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.partialTranscript = ""
                await self?.send(text)
            }
        }
        voice.onTranscriptPartial = { [weak self] text in
            Task { @MainActor [weak self] in self?.partialTranscript = text }
        }
        voice.onAudioLevel = { [weak self] level in
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }
        voice.onReadyToListen = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.fluidListening else { return }
                self.startListening()
            }
        }

        // Restore local cache if available (Supabase may not be reachable yet)
        if let cached = SupabaseClient.shared.loadCachedSession() {
            currentConversationId = cached.conversationId
            messages = cached.messages
        }
    }

    // MARK: - Startup

    func startup() async {
        await LumenAPIManager.shared.resolveBaseURL()
        await LumenAPIManager.shared.loadMemoryContext()
    }

    // MARK: - Dashboard (nexus-web)

    func fetchDashboard() async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/dashboard/overview") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let rawAgents = json["agents"] as? [[String: Any]] {
            agents = rawAgents.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let status        = dict["status"] as? String ?? "standby"
                let role          = dict["role"]   as? String ?? "Nexus Agent"
                let totalFindings = dict["total_findings"] as? Int ?? 0
                let lastScanned   = dict["last_scanned_at"] as? String
                let lastAction: String = {
                    guard let scanned = lastScanned, !scanned.isEmpty else { return "Never scanned" }
                    let iso  = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let date = iso.date(from: scanned) ?? ISO8601DateFormatter().date(from: scanned)
                    let label = date.map { d in
                        let s = -d.timeIntervalSinceNow
                        if s < 3600  { return "\(Int(s/60))m ago" }
                        if s < 86400 { return "\(Int(s/3600))h ago" }
                        return "\(Int(s/86400))d ago"
                    } ?? scanned
                    return "\(totalFindings) findings · \(label)"
                }()
                return AgentStatus(name: name, role: role, status: status, lastAction: lastAction)
            }
        }

        if let rawOps = json["operations"] as? [[String: Any]] {
            operations = rawOps.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let status   = dict["status"]   as? String ?? "active"
                let priority = dict["priority"] as? String ?? "medium"
                let codename = dict["codename"] as? String ?? name.uppercased()
                return OperationItem(codename: codename, name: name, status: status, priority: priority)
            }
        }
    }

    // MARK: - Conversation history (direct Supabase)

    func fetchConversations() async {
        conversations = await SupabaseClient.shared.fetchConversations()
    }

    func loadConversation(id: String, title: String) async {
        let msgs = await SupabaseClient.shared.fetchMessages(conversationId: id)
        loadedHistoryTitle = title
        loadedHistory = msgs
    }

    func clearHistory() {
        loadedHistory = []
        loadedHistoryTitle = nil
    }

    func newConversation() {
        currentConversationId = nil
        messages = []
        lastError = nil
    }

    // MARK: - Chat

    func send(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: text))
        eveStatus = .thinking
        lastError = nil

        // UI shortcut commands
        let lower = text.lowercased()
        if lower.contains("show") && lower.contains("agent") {
            activePanel = .agents
            eveStatus   = .speaking
            speak("Pulling up agent status now, sir.")
            return
        }
        if lower.contains("show") && (lower.contains("operation") || lower.contains("ops")) {
            activePanel = .operations
            eveStatus   = .speaking
            speak("Here are your active operations.")
            return
        }
        if lower.contains("close") {
            activePanel = .none
            eveStatus   = .idle
            return
        }

        do {
            let response = try await api.chat(message: text, history: messages.dropLast())
            let assistantMsg = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMsg)
            eveStatus = .speaking
            speak(response)

            // Persist to Supabase + local cache (fire-and-forget)
            Task {
                let convId = await ensureConversation(firstMessage: text)
                await SupabaseClient.shared.saveMessage(conversationId: convId, role: "user",      content: text)
                await SupabaseClient.shared.saveMessage(conversationId: convId, role: "assistant", content: response)
                await SupabaseClient.shared.touchConversation(id: convId)
                SupabaseClient.shared.cacheSession(conversationId: convId, messages: messages)
            }
        } catch {
            let errMsg = "LM Studio unreachable. Ensure it is running at localhost:1234."
            lastError  = errMsg
            messages.append(ChatMessage(role: .assistant, content: errMsg))
            eveStatus = .speaking
            speak("I can't reach my local brain right now, sir. Check LM Studio.")
        }
    }

    // Returns existing conversationId or creates a new one in Supabase
    private func ensureConversation(firstMessage: String) async -> String {
        if let id = currentConversationId { return id }

        let title  = String(firstMessage.prefix(60))
        let newId  = await SupabaseClient.shared.createConversation(title: title) ?? UUID().uuidString
        await MainActor.run { currentConversationId = newId }
        return newId
    }

    // MARK: - Voice

    func speak(_ text: String) {
        voice.speak(text) { [weak self] in
            Task { @MainActor [weak self] in self?.eveStatus = .idle }
        }
    }

    func startListening() {
        fluidListening    = true
        eveStatus         = .listening
        partialTranscript = ""
        voice.startListening()
    }

    func stopListening() {
        fluidListening = false
        voice.stopListening()
        if eveStatus == .listening { eveStatus = .idle }
    }
}
