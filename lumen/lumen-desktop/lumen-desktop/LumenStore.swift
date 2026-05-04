import SwiftUI
import Combine

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String           // var so streaming can append in place
    let timestamp = Date()
    enum Role { case user, assistant }
}

struct AgentStatus: Identifiable {
    let id = UUID()
    let agentId: String        // real DB id
    let name: String
    let role: String
    let status: String
    let lastAction: String
    let totalFindings: Int
}

struct OperationItem: Identifiable {
    let id = UUID()
    let operationId: String    // real DB id
    let codename: String
    let name: String
    let status: String
    let priority: String
    let description: String
}

struct ConversationSummary: Identifiable {
    let id: String
    let title: String
    let source: String
    let updatedAt: Date
    var preview: String = ""
    var messageCount: Int = 0
}

struct DirectiveItem: Identifiable {
    let id: String
    let type: String     // directive | protocol | rule
    let title: String
    let content: String
    let priority: Int
    let target: String
    let isActive: Bool
}

struct MemoryItem: Identifiable {
    let id: String
    let type: String     // fact | task | objective | preference
    let content: String
    let priority: Int
    let source: String
    let updatedAt: String
}

struct OperationRecord: Identifiable {
    let id: String
    let title: String
    let content: String
    let type: String       // intel | finding | data | alert | note
    let priority: String   // critical | high | normal | low
    let source: String
    let createdAt: String
    let pinned: Bool
}

struct AgentActivity: Identifiable {
    let id: String
    let action: String         // scan_completed | finding_created | batch_completed | …
    let summary: String        // human-readable line built from details JSON
    let createdAt: String
}

struct OperationBrief: Identifiable {
    var id: String { kind }
    let kind: String           // summary | actions | contradictions | themes | next-steps
    let content: String        // markdown-ish
    let generatedAt: String
}

struct NexusMapNode: Identifiable, Hashable {
    let id: String              // raw id from /api/nexus-map (e.g. "op-uuid", "rec-uuid", "agent-uuid", or bare uuid for conversations)
    let type: String            // conversation | agent | operation | record | research | directive | topic | human
    let title: String
    let subtitle: String
    let preview: String
    let tags: [String]
    let status: String?
    let priority: String?
    let pinned: Bool
    let archived: Bool
    let messageCount: Int
    let createdAt: String
    let updatedAt: String
    let parentId: String?
    let sourceConversationId: String?
}

struct NexusMapEdge: Identifiable, Hashable {
    let source: String
    let target: String
    let type: String
    var id: String { "\(source)→\(target):\(type)" }
}

struct NexusMapData {
    var nodes: [NexusMapNode]
    var edges: [NexusMapEdge]
    var activeResearch: Int
    var fetchedAt: Date
    static let empty = NexusMapData(nodes: [], edges: [], activeResearch: 0, fetchedAt: .distantPast)
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
        case .idle:      return .secondary
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
    @Published var directives: [DirectiveItem] = []
    @Published var memories: [MemoryItem] = []
    @Published var recordsByOp: [String: [OperationRecord]] = [:]
    @Published var activityByAgent: [String: [AgentActivity]] = [:]
    @Published var briefsByOp: [String: [String: OperationBrief]] = [:]
    @Published var briefGenerating: String? = nil  // "<opId>:<kind>" while regenerating
    @Published var agentChats: [String: [ChatMessage]] = [:]  // history per agent
    @Published var agentChatSending: String? = nil            // agentId currently awaiting reply
    @Published var pendingImages: [String] = []  // base64 strings, sent on next message
    @Published var commandPaletteVisible: Bool = false
    @Published var nexusMap: NexusMapData = .empty
    @Published var nexusMapLoading: Bool = false

    private static let preferLocalKey = "lumen.preferLocalBrain"
    /// When true, `send()` tries local Ollama first and falls back to nexus-web Eve.
    /// When false (default), uses nexus-web Eve (Grok + tools) as primary.
    @Published var preferLocalBrain: Bool = UserDefaults.standard.bool(forKey: preferLocalKey) {
        didSet { UserDefaults.standard.set(preferLocalBrain, forKey: Self.preferLocalKey) }
    }
    @Published var loadedHistory: [ChatMessage] = []
    @Published var loadedHistoryTitle: String? = nil
    @Published var currentConversationTitle: String? = nil
    @Published var agentRecords: [String: [String: String]] = [:]
    @Published var operationRecords: [String: [String: String]] = [:]
    @Published var dashboardRecords: [String: [String: String]] = [:]

    private var titleGenerated = false

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
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        dashboardRecords = flattenTopLevel(json)

        if let rawAgents = json["agents"] as? [[String: Any]] {
            agentRecords = Dictionary(
                uniqueKeysWithValues: rawAgents.compactMap { dict in
                    guard let id = dict["id"] as? String else { return nil }
                    return (id, flatten(dict))
                }
            )
            agents = rawAgents.compactMap { dict in
                guard let name    = dict["name"] as? String else { return nil }
                guard let agentId = dict["id"]   as? String else { return nil }
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
                return AgentStatus(agentId: agentId, name: name, role: role, status: status, lastAction: lastAction, totalFindings: totalFindings)
            }
        }

        if let rawOps = json["operations"] as? [[String: Any]] {
            operationRecords = Dictionary(
                uniqueKeysWithValues: rawOps.compactMap { dict in
                    guard let id = dict["id"] as? String else { return nil }
                    return (id, flatten(dict))
                }
            )
            operations = makeOperations(from: rawOps)
        }
    }

    func fetchOperations() async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/operations") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return }

        let rawOps = extractOperationPayload(from: json)
        guard !rawOps.isEmpty else { return }

        operationRecords = Dictionary(
            uniqueKeysWithValues: rawOps.compactMap { dict in
                guard let id = dict["id"] as? String else { return nil }
                return (id, flatten(dict))
            }
        )
        operations = makeOperations(from: rawOps)
    }

    private func flattenTopLevel(_ dictionary: [String: Any]) -> [String: [String: String]] {
        Dictionary(
            uniqueKeysWithValues: dictionary.map { key, value in
                if let nested = value as? [String: Any] {
                    return (key, flatten(nested))
                }
                if let array = value as? [[String: Any]] {
                    let summary: [String: String] = [
                        "count": "\(array.count)",
                        "preview": array.prefix(3).map { flatten($0).map { "\($0.key)=\($0.value)" }.joined(separator: ", ") }.joined(separator: "\n\n")
                    ]
                    return (key, summary)
                }
                return (key, ["value": stringify(value)])
            }
        )
    }

    private func flatten(_ dictionary: [String: Any], prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            switch value {
            case let nested as [String: Any]:
                flatten(nested, prefix: path).forEach { result[$0.key] = $0.value }
            case let array as [[String: Any]]:
                result["\(path).count"] = "\(array.count)"
                for (index, item) in array.prefix(5).enumerated() {
                    flatten(item, prefix: "\(path)[\(index)]").forEach { result[$0.key] = $0.value }
                }
            case let array as [Any]:
                result[path] = array.map(stringify).joined(separator: ", ")
            default:
                result[path] = stringify(value)
            }
        }

        return result
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case is NSNull:
            return "null"
        default:
            return String(describing: value)
        }
    }

    private func extractOperationPayload(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] {
            return array
        }
        guard let dict = json as? [String: Any] else { return [] }
        if let operations = dict["operations"] as? [[String: Any]] {
            return operations
        }
        if let data = dict["data"] as? [[String: Any]] {
            return data
        }
        if let items = dict["items"] as? [[String: Any]] {
            return items
        }
        return []
    }

    private func makeOperations(from rawOps: [[String: Any]]) -> [OperationItem] {
        rawOps.compactMap { dict in
            guard let operationId = dict["id"] as? String else { return nil }
            let name = (dict["name"] as? String)
                ?? (dict["title"] as? String)
                ?? (dict["objective"] as? String)
                ?? "Untitled Operation"
            let status = dict["status"] as? String ?? "active"
            let priority = dict["priority"] as? String ?? "medium"
            let codename = (dict["codename"] as? String)
                ?? (dict["code_name"] as? String)
                ?? name.uppercased()
            let description = (dict["description"] as? String)
                ?? (dict["summary"] as? String)
                ?? (dict["objective"] as? String)
                ?? ""
            return OperationItem(
                operationId: operationId,
                codename: codename,
                name: name,
                status: status,
                priority: priority,
                description: description
            )
        }
    }

    // MARK: - Conversation history (direct Supabase)

    // MARK: - Directives + Memory

    func fetchDirectives() async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/directives") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["directives"] as? [[String: Any]] else { return }
        directives = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let type = d["type"] as? String,
                  let title = d["title"] as? String,
                  let content = d["content"] as? String else { return nil }
            return DirectiveItem(
                id: id,
                type: type,
                title: title,
                content: content,
                priority: d["priority"] as? Int ?? 0,
                target: d["target"] as? String ?? "all",
                isActive: d["is_active"] as? Bool ?? true
            )
        }
    }

    func fetchMemories() async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/memory") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["memories"] as? [[String: Any]] else { return }
        memories = raw.compactMap { m in
            guard let id = m["id"] as? String,
                  let content = m["content"] as? String else { return nil }
            return MemoryItem(
                id: id,
                type: m["type"] as? String ?? "fact",
                content: content,
                priority: m["priority"] as? Int ?? 5,
                source: m["source"] as? String ?? "manual",
                updatedAt: m["updated_at"] as? String ?? ""
            )
        }
    }

    // MARK: - Nexus Map (the universe view)

    func fetchNexusMap() async {
        nexusMapLoading = true
        defer { nexusMapLoading = false }
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/nexus-map") else { return }
        var req = URLRequest(url: url, timeoutInterval: 30)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let rawNodes = json["nodes"] as? [[String: Any]] ?? []
        let rawEdges = json["edges"] as? [[String: Any]] ?? []
        let activeResearch = json["activeResearch"] as? Int ?? 0

        let parsedNodes: [NexusMapNode] = rawNodes.compactMap { d in
            guard let id = d["id"] as? String, let type = d["type"] as? String, let title = d["title"] as? String else { return nil }
            return NexusMapNode(
                id: id,
                type: type,
                title: title,
                subtitle: d["subtitle"] as? String ?? "",
                preview: d["preview"] as? String ?? "",
                tags: d["tags"] as? [String] ?? [],
                status: d["status"] as? String,
                priority: d["priority"] as? String,
                pinned: d["pinned"] as? Bool ?? false,
                archived: d["archived"] as? Bool ?? false,
                messageCount: d["messageCount"] as? Int ?? 0,
                createdAt: d["createdAt"] as? String ?? "",
                updatedAt: d["updatedAt"] as? String ?? "",
                parentId: d["parentId"] as? String,
                sourceConversationId: d["sourceConversationId"] as? String
            )
        }
        let parsedEdges: [NexusMapEdge] = rawEdges.compactMap { d in
            guard let s = d["source"] as? String, let t = d["target"] as? String, let ty = d["type"] as? String else { return nil }
            return NexusMapEdge(source: s, target: t, type: ty)
        }

        nexusMap = NexusMapData(nodes: parsedNodes, edges: parsedEdges, activeResearch: activeResearch, fetchedAt: Date())
    }

    // MARK: - Image attachment (vision)

    func attachImage(at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        // Cap at 5MB raw to keep payload reasonable
        guard data.count <= 5 * 1024 * 1024 else { return }
        let b64 = data.base64EncodedString()
        pendingImages.append(b64)
    }

    func removeImage(at index: Int) {
        guard index < pendingImages.count else { return }
        pendingImages.remove(at: index)
    }

    func clearPendingImages() { pendingImages.removeAll() }

    // MARK: - Agent Activity

    func fetchAgentActivity(id: String) async {
        let base = LumenAPIManager.shared.nexusBase
        guard var comps = URLComponents(string: "\(base)/api/agents/activity") else { return }
        comps.queryItems = [
            URLQueryItem(name: "agent_id", value: id),
            URLQueryItem(name: "limit", value: "30"),
        ]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["activity"] as? [[String: Any]] else { return }

        let items: [AgentActivity] = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let action = d["action"] as? String else { return nil }
            let details = d["details"] as? [String: Any] ?? [:]
            return AgentActivity(
                id: id,
                action: action,
                summary: Self.describeActivity(action: action, details: details),
                createdAt: d["created_at"] as? String ?? ""
            )
        }
        activityByAgent[id] = items
    }

    private static func describeActivity(action: String, details: [String: Any]) -> String {
        switch action {
        case "scan_completed":
            let f = details["findings_created"] as? Int ?? 0
            let c = details["conversations_scanned"] as? Int ?? 0
            return "Scan complete · \(f) findings from \(c) conversations"
        case "batch_completed":
            let i = details["batch_index"] as? Int ?? 0
            let n = details["findings_so_far"] as? Int ?? 0
            return "Batch \(i + 1) · \(n) findings so far"
        case "finding_created":
            let title = details["title"] as? String ?? "(untitled)"
            let type = details["type"] as? String ?? "finding"
            return "\(type.uppercased()): \(title)"
        case "scan_started":
            return "Scan started"
        case "scan_failed":
            return "Scan failed: \(details["error"] as? String ?? "unknown")"
        case "status_change":
            return "Status: \(details["from"] as? String ?? "?") → \(details["to"] as? String ?? "?")"
        default:
            return action.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: - Agent Chat

    func sendAgentChat(agentId: String, message: String) async {
        let prior = agentChats[agentId] ?? []
        var withUser = prior
        withUser.append(ChatMessage(role: .user, content: message))
        agentChats[agentId] = withUser
        agentChatSending = agentId
        defer { agentChatSending = nil }

        let payload = withUser.suffix(10).map { (role: $0.role == .user ? "user" : "assistant", content: $0.content) }
        do {
            let reply = try await LumenAPIManager.shared.chatWithAgent(
                agentId: agentId,
                message: message,
                history: Array(payload.dropLast())  // server appends current msg itself
            )
            var updated = agentChats[agentId] ?? []
            updated.append(ChatMessage(role: .assistant, content: reply))
            agentChats[agentId] = updated
        } catch {
            var updated = agentChats[agentId] ?? []
            updated.append(ChatMessage(role: .assistant, content: "Comms link failed."))
            agentChats[agentId] = updated
        }
    }

    func clearAgentChat(agentId: String) {
        agentChats[agentId] = []
    }

    // MARK: - Operation Briefs

    func fetchBriefs(opId: String) async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/operations/\(opId)/briefs") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var bag: [String: OperationBrief] = [:]
        for (kind, value) in json {
            if let b = value as? [String: Any],
               let content = b["content"] as? String {
                bag[kind] = OperationBrief(
                    kind: kind,
                    content: content,
                    generatedAt: b["generated_at"] as? String ?? ""
                )
            }
        }
        briefsByOp[opId] = bag
    }

    func regenerateBrief(opId: String, kind: String) async {
        briefGenerating = "\(opId):\(kind)"
        defer { briefGenerating = nil }
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/operations/\(opId)/briefs") else { return }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["kind": kind])
        _ = try? await URLSession.shared.data(for: req)
        await fetchBriefs(opId: opId)
    }

    // MARK: - Operation Records

    func fetchRecords(opId: String) async {
        let base = LumenAPIManager.shared.nexusBase
        guard var comps = URLComponents(string: "\(base)/api/operations/records") else { return }
        comps.queryItems = [URLQueryItem(name: "operation_id", value: opId)]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let parsed: [OperationRecord] = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let title = d["title"] as? String else { return nil }
            return OperationRecord(
                id: id,
                title: title,
                content: d["content"] as? String ?? "",
                type: d["type"] as? String ?? "note",
                priority: d["priority"] as? String ?? "normal",
                source: d["source"] as? String ?? "manual",
                createdAt: d["created_at"] as? String ?? "",
                pinned: d["pinned"] as? Bool ?? false
            )
        }
        recordsByOp[opId] = parsed
    }

    func addRecord(opId: String, title: String, content: String, type: String) async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/operations/records") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "operation_id": opId, "title": title, "content": content, "type": type
        ])
        _ = try? await URLSession.shared.data(for: req)
        await fetchRecords(opId: opId)
    }

    func toggleDirective(_ item: DirectiveItem) async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/directives") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": item.id, "is_active": !item.isActive])
        _ = try? await URLSession.shared.data(for: req)
        await fetchDirectives()
    }

    func createDirective(type: String, title: String, content: String, priority: Int, target: String) async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/directives") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": type, "title": title, "content": content, "priority": priority, "target": target
        ])
        _ = try? await URLSession.shared.data(for: req)
        await fetchDirectives()
    }

    func createMemory(type: String, content: String, priority: Int) async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/memory") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "type": type, "content": content, "priority": priority, "source": "manual"
        ])
        _ = try? await URLSession.shared.data(for: req)
        await fetchMemories()
    }

    func deleteMemory(_ item: MemoryItem) async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/memory") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": item.id])
        _ = try? await URLSession.shared.data(for: req)
        await fetchMemories()
    }

    func fetchConversations() async {
        // Prefer nexus-web's /api/eve/conversations — returns preview + count.
        // Falls back to direct Supabase REST if nexus-web is unreachable.
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/conversations") else {
            conversations = await SupabaseClient.shared.fetchConversations()
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["conversations"] as? [[String: Any]] else {
            conversations = await SupabaseClient.shared.fetchConversations()
            return
        }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        conversations = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let title = d["title"] as? String else { return nil }
            let upd = d["updated_at"] as? String ?? ""
            let date = isoFull.date(from: upd) ?? isoBasic.date(from: upd) ?? Date.distantPast
            return ConversationSummary(
                id: id,
                title: title,
                source: d["source"] as? String ?? "lumen",
                updatedAt: date,
                preview: d["preview"] as? String ?? "",
                messageCount: d["message_count"] as? Int ?? 0
            )
        }
    }

    func loadConversation(id: String, title: String) async {
        let msgs = await SupabaseClient.shared.fetchMessages(conversationId: id)
        currentConversationId = id
        currentConversationTitle = title
        messages = msgs
        loadedHistory = []
        loadedHistoryTitle = nil
        lastError = nil
        titleGenerated = msgs.count >= 6
        SupabaseClient.shared.cacheSession(conversationId: id, messages: msgs)
    }

    func clearHistory() {
        loadedHistory = []
        loadedHistoryTitle = nil
    }

    func newConversation() {
        currentConversationId = nil
        currentConversationTitle = nil
        messages = []
        lastError = nil
        titleGenerated = false
        loadedHistory = []
        loadedHistoryTitle = nil
    }

    // MARK: - Chat

    func send(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Vision branch — if the Director has attached images, route through
        // /api/eve/local which auto-selects llava when images are present.
        if !pendingImages.isEmpty {
            await sendWithVision(text: text)
            return
        }

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
            // Brain selection: when preferLocalBrain is on, try local Ollama
            // FIRST (with streaming), and only fall back to nexus-web Eve if
            // Ollama errors. Default is the reverse: nexus-web Eve (Grok +
            // tools) primary, local fallback.
            let response: String
            var nexusConvId: String? = nil

            if preferLocalBrain {
                // Local-primary path — full streaming, no tool calls.
                messages.append(ChatMessage(role: .assistant, content: ""))
                let streamIdx = messages.count - 1
                eveStatus = .speaking
                do {
                    response = try await api.callLocalLLMStreaming(
                        message: text,
                        history: messages.dropFirst().dropLast()
                    ) { [weak self] delta in
                        guard let self else { return }
                        guard streamIdx < self.messages.count else { return }
                        self.messages[streamIdx].content += delta
                    }
                    speak(response)
                    eveStatus = .idle
                    let snapshot = messages
                    Task {
                        let convId = await ensureConversation(firstMessage: text)
                        await SupabaseClient.shared.saveMessage(conversationId: convId, role: "user",      content: text)
                        await SupabaseClient.shared.saveMessage(conversationId: convId, role: "assistant", content: response)
                        await SupabaseClient.shared.touchConversation(id: convId)
                        SupabaseClient.shared.cacheSession(conversationId: convId, messages: snapshot)
                        await maybeGenerateTitle(conversationId: convId, history: snapshot)
                    }
                    return
                } catch {
                    // Local stream failed — drop placeholder and try nexus-web Grok
                    messages.removeLast()
                }
            }

            do {
                let result = try await api.callNexusEve(
                    message: text,
                    conversationId: currentConversationId,
                    history: messages.dropLast()
                )
                response    = result.content
                nexusConvId = result.conversationId
                if let newId = nexusConvId, currentConversationId == nil {
                    currentConversationId = newId
                }
                if currentConversationTitle == nil {
                    currentConversationTitle = String(text.prefix(60))
                }
            } catch {
                // Nexus-web unavailable — stream from local Ollama so Eve text
                // appears token-by-token. Fall back to Claude only if Ollama
                // also fails. Insert a placeholder we mutate as deltas arrive.
                messages.append(ChatMessage(role: .assistant, content: ""))
                let streamIdx = messages.count - 1
                eveStatus = .speaking  // orb starts pulsing the moment text begins

                do {
                    response = try await api.callLocalLLMStreaming(
                        message: text,
                        history: messages.dropFirst().dropLast()  // drop placeholder + this user turn
                    ) { [weak self] delta in
                        guard let self else { return }
                        guard streamIdx < self.messages.count else { return }
                        self.messages[streamIdx].content += delta
                    }
                } catch {
                    // Local stream failed — try Claude as final fallback
                    messages.removeLast()
                    response = try await api.chat(message: text, history: messages.dropLast())
                    messages.append(ChatMessage(role: .assistant, content: response))
                }
                speak(response)
                eveStatus = .idle

                // Local-brain branch handles its own persistence below.
                let snapshot = messages
                Task {
                    let convId = await ensureConversation(firstMessage: text)
                    await SupabaseClient.shared.saveMessage(conversationId: convId, role: "user",      content: text)
                    await SupabaseClient.shared.saveMessage(conversationId: convId, role: "assistant", content: response)
                    await SupabaseClient.shared.touchConversation(id: convId)
                    SupabaseClient.shared.cacheSession(conversationId: convId, messages: snapshot)
                    await maybeGenerateTitle(conversationId: convId, history: snapshot)
                }
                return
            }

            let assistantMsg = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMsg)
            eveStatus = .speaking
            speak(response)

            // Persist locally if nexus-web didn't handle it
            if nexusConvId == nil {
                let snapshot = messages
                Task {
                    let convId = await ensureConversation(firstMessage: text)
                    await SupabaseClient.shared.saveMessage(conversationId: convId, role: "user",      content: text)
                    await SupabaseClient.shared.saveMessage(conversationId: convId, role: "assistant", content: response)
                    await SupabaseClient.shared.touchConversation(id: convId)
                    SupabaseClient.shared.cacheSession(conversationId: convId, messages: snapshot)
                    await maybeGenerateTitle(conversationId: convId, history: snapshot)
                }
            }
        } catch {
            let errMsg = "Eve is offline — nexus-web and local brain both unreachable."
            lastError  = errMsg
            messages.append(ChatMessage(role: .assistant, content: errMsg))
            eveStatus = .speaking
            speak("All systems offline, sir. Check nexus-web and your API keys.")
        }
    }

    /// Single-shot vision request via /api/eve/local + llava. Pending images
    /// are sent once and cleared. Falls back to a friendly error message on failure.
    private func sendWithVision(text: String) async {
        let prompt = text.isEmpty ? "What do you see, Eve?" : text
        let imgs = pendingImages
        clearPendingImages()
        messages.append(ChatMessage(role: .user, content: "\(prompt)  📷×\(imgs.count)"))
        eveStatus = .thinking
        lastError = nil

        do {
            let result = try await api.callLocalEveWithImages(
                message: prompt,
                images: imgs,
                conversationId: currentConversationId
            )
            if let newId = result.conversationId, currentConversationId == nil {
                currentConversationId = newId
            }
            messages.append(ChatMessage(role: .assistant, content: result.content))
            eveStatus = .speaking
            speak(result.content)
        } catch {
            lastError = "Vision request failed."
            messages.append(ChatMessage(role: .assistant, content: "I couldn't process the image, sir."))
            eveStatus = .speaking
            speak("Vision pipeline returned an error.")
        }
    }

    private func maybeGenerateTitle(conversationId: String, history: [ChatMessage]) async {
        guard !titleGenerated, history.count >= 6 else { return }
        titleGenerated = true
        if let title = await LumenAPIManager.shared.generateTitle(history: history) {
            await SupabaseClient.shared.updateConversationTitle(id: conversationId, title: title)
        }
    }

    // Returns existing conversationId or creates a new one in Supabase
    private func ensureConversation(firstMessage: String) async -> String {
        if let id = currentConversationId { return id }

        let title  = String(firstMessage.prefix(60))
        let newId  = await SupabaseClient.shared.createConversation(title: title) ?? UUID().uuidString
        await MainActor.run {
            currentConversationId = newId
            currentConversationTitle = title
        }
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
