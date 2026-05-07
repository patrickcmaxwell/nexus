import SwiftUI
import AppKit
import Combine
import UserNotifications

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String           // var so streaming can append in place
    let timestamp = Date()
    /// Which brain produced this assistant reply: "grok" | "local" | "claude" | "vision" | "offline".
    /// `nil` for user messages and historical loads where the source isn't recorded.
    var brain: String? = nil
    /// Tool calls Eve fired while producing this reply — rendered as visible
    /// chips inside the message so her actions are no longer invisible.
    var toolCalls: [ToolCallSummary] = []
    enum Role { case user, assistant }
}

/// "What changed since last visit" delta from `/api/eve/briefing`.
struct BriefingDelta {
    var since: Date
    var fetchedAt: Date
    var activeOps: Int
    var activeAgents: Int
    var activeDirectives: Int
    var memories: Int
    var newOperations: [BriefingOpItem]
    var statusChangedOperations: [BriefingOpItem]
    var newRecords: [BriefingRecordItem]
    var findingTotal: Int
    var findingsPerAgent: [(name: String, count: Int)]
    var completedResearch: [BriefingResearchItem]
    var hasAnyDelta: Bool {
        !newOperations.isEmpty
            || !statusChangedOperations.isEmpty
            || !newRecords.isEmpty
            || findingTotal > 0
            || !completedResearch.isEmpty
    }
    static let empty = BriefingDelta(
        since: .distantPast, fetchedAt: .distantPast,
        activeOps: 0, activeAgents: 0, activeDirectives: 0, memories: 0,
        newOperations: [], statusChangedOperations: [],
        newRecords: [], findingTotal: 0, findingsPerAgent: [],
        completedResearch: []
    )
}

struct BriefingOpItem: Identifiable, Hashable {
    let id: String
    let label: String
    let status: String
    let priority: String
}

struct BriefingRecordItem: Identifiable, Hashable {
    let id: String
    let title: String
    let type: String
    let operationLabel: String
}

struct BriefingResearchItem: Identifiable, Hashable {
    let id: String
    let operationLabel: String
    let summary: String
}

/// Display-ready record of a single tool Eve invoked in a turn.
struct ToolCallSummary: Hashable, Identifiable {
    let id: UUID = UUID()
    let name: String         // raw tool name (e.g., arena_task_create)
    let humanLabel: String   // "Created task", "Logged action", etc.
    let primary: String      // headline value: title, name, summary
    let detail: String       // secondary line: id / status / count
    let success: Bool

    /// Map a raw `{name, args, result}` tuple from /api/eve into a chip-ready summary.
    static func from(rawName: String, args: [String: Any], result: [String: Any]) -> ToolCallSummary {
        let success = (result["success"] as? Bool) ?? true
        let err = result["error"] as? String

        switch rawName {
        case "arena_task_create":
            let title = (args["title"] as? String) ?? "Untitled task"
            let assignee = args["assignee"] as? String
            let id = result["task_id"] as? String ?? ""
            let detail = [id, assignee.map { "→ \($0)" }].compactMap { $0 }.filter { !($0?.isEmpty ?? true) }.compactMap { $0 }.joined(separator: " ")
            return ToolCallSummary(name: rawName, humanLabel: "Created task",
                                    primary: title, detail: success ? detail : (err ?? "failed"), success: success)
        case "arena_task_update":
            let id = (args["task_id"] as? String) ?? ""
            let status = (args["status"] as? String) ?? "updated"
            return ToolCallSummary(name: rawName, humanLabel: "Updated task",
                                    primary: id, detail: success ? status.uppercased() : (err ?? "failed"), success: success)
        case "arena_payment_route":
            let amount = (args["amount"] as? Double).map { String(format: "$%.2f", $0) }
                ?? (args["amount"] as? Int).map { "$\($0)" }
                ?? "?"
            let ref = (args["reference"] as? String) ?? ""
            return ToolCallSummary(name: rawName, humanLabel: "Routed payment",
                                    primary: amount, detail: success ? ref : (err ?? "failed"), success: success)
        case "arena_sync_push":
            return ToolCallSummary(name: rawName, humanLabel: "Pushed memory sync",
                                    primary: "Memory bank", detail: success ? "synced" : (err ?? "failed"), success: success)
        case "arena_recent":
            let entries = (result["entries"] as? [Any])?.count ?? 0
            return ToolCallSummary(name: rawName, humanLabel: "Read Arena log",
                                    primary: "\(entries) entries", detail: "", success: success)
        default:
            // Unknown tool — render generically.
            let primary = (args["title"] as? String)
                ?? (args["name"] as? String)
                ?? (args["content"] as? String).map { String($0.prefix(40)) }
                ?? rawName
            return ToolCallSummary(name: rawName, humanLabel: rawName.replacingOccurrences(of: "_", with: " ").capitalized,
                                    primary: primary,
                                    detail: success ? "ok" : (err ?? "failed"),
                                    success: success)
        }
    }
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

/// One row from /api/eve/search — a conversation that matched the query
/// either by title or by message content.
struct CrossThreadSearchHit: Identifiable, Hashable {
    let id: String           // conversation_id, also acts as Identifiable id
    let conversationId: String
    let title: String
    let source: String
    let snippet: String
    let matchType: String    // "title" | "content" | "both"
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
    @Published var eveStatus: EveStatus = .idle {
        didSet { updateThinkingHeartbeat() }
    }
    @Published var activePanel: ActivePanel = .none
    @Published var audioLevel: Float = 0
    @Published var partialTranscript: String = ""
    @Published var lastError: String? = nil
    @Published var fluidListening: Bool = false

    /// Identifier of the chat surface that currently owns the mic. nil =
    /// nobody (idle), "main" = the main chat thread, anything else = a
    /// per-conversation pop-out window's conversationId. Exclusive — only
    /// one surface can claim the mic at a time, since macOS gives us one mic.
    @Published var voiceClaimedBy: String? = nil

    /// Callback the claiming surface registers — receives every final
    /// transcript so it can append to its own message list and submit on its
    /// own conversationId. When nil, falls back to the main thread's `send()`.
    private var voiceTranscriptHandler: ((String) -> Void)?

    /// User-controlled mute within an active voice session. When true:
    ///   - The mic does NOT listen for new input (recognition stops).
    ///   - Barge-in detection is suspended (Eve won't be interrupted by
    ///     incidental sounds — coughs, breaths, side conversation).
    ///   - When Director toggles back to unmuted, listening resumes.
    /// This lets the Director enter voice mode once and stay in it, muting
    /// briefly when they want to hear Eve out without accidental interrupts.
    @Published var userMuted: Bool = false

    /// True for the next call to `send()` if the user got here by speaking
    /// (transcript came from `voice.onTranscriptFinal`). Voice-originated
    /// turns prefer local Ollama (sub-second first token, no cloud round-trip)
    /// so conversation feels fluid. Typed turns keep the existing routing
    /// (Grok with full tool access when needed). One-shot — reset after each send.
    private var voiceOriginatedTurn: Bool = false

    /// Synthetic 1Hz heartbeat that drives `audioLevel` while Eve is
    /// `.thinking` — gives the orb obvious motion BEFORE her voice starts so
    /// the Director sees "she's processing" not "she's frozen". Stops the
    /// moment she transitions to `.speaking` (where real TTS amplitude
    /// takes over via the metering loop in EveVoiceManager).
    private var thinkingHeartbeatTimer: Timer?
    private func updateThinkingHeartbeat() {
        thinkingHeartbeatTimer?.invalidate()
        thinkingHeartbeatTimer = nil
        guard eveStatus == .thinking else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.eveStatus == .thinking else { return }
            // 1Hz cosine envelope, 0…1 range, with a soft floor so the orb
            // never flatlines.
            let t = Date().timeIntervalSinceReferenceDate
            let phase = (1 - cos(t * .pi * 2 / 1.0)) / 2  // 1Hz, 0…1
            let level = Float(0.20 + phase * 0.55)         // 0.20…0.75
            DispatchQueue.main.async { self.audioLevel = level }
        }
        RunLoop.main.add(timer, forMode: .common)
        thinkingHeartbeatTimer = timer
    }

    @Published var agents: [AgentStatus] = []
    @Published var operations: [OperationItem] = []
    @Published var conversations: [ConversationSummary] = []

    /// Top-level UI mode for the main window. Dashboard is the new default
    /// landing — Eve gives a state-of-affairs mission report and the Director
    /// chooses whether to engage an existing thread or open a fresh one.
    /// `.live` switches to the active conversation thread.
    enum ViewMode: String { case dashboard, live }
    @Published var viewMode: ViewMode = .dashboard

    /// Reply target. When set, the composer renders a quoted preview chip
    /// above the input, and the next submitted message is prefixed with a
    /// short blockquote of the targeted text. Cleared automatically after
    /// `send` runs (or manually via `clearReplyTarget()`).
    @Published var replyTarget: ChatMessage? = nil

    /// One-tap "Reply to this Eve message" — also moves keyboard focus into
    /// the composer via the inputFocused FocusState that MainView watches.
    func setReplyTarget(_ message: ChatMessage) {
        replyTarget = message
        NotificationCenter.default.post(name: .lumenComposerFocus, object: nil)
    }

    func clearReplyTarget() {
        replyTarget = nil
    }

    /// Compose-time prefix derived from the active reply target. Returns
    /// "" when nothing's pinned. Truncates the quote so a long Eve message
    /// doesn't dominate the user's reply.
    func consumeReplyPrefix() -> String {
        guard let target = replyTarget else { return "" }
        let raw = target.content
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet: String = {
            let max = 240
            if raw.count <= max { return raw }
            return String(raw.prefix(max)) + "…"
        }()
        let quoted = snippet
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        replyTarget = nil
        return "\(quoted)\n\n"
    }

    /// Switch to live mode and (optionally) load a specific conversation.
    /// Pass nil to open a fresh thread (preserves any in-flight messages
    /// the user may have already started).
    func engageLive(conversationId: String? = nil, title: String? = nil) {
        if let cid = conversationId {
            Task { @MainActor in
                await loadConversation(id: cid, title: title ?? "Conversation")
                viewMode = .live
            }
        } else {
            // Fresh start
            newConversation()
            viewMode = .live
        }
    }

    /// Return to the dashboard without losing the current conversation.
    /// `currentConversationId` and `messages` are preserved so re-engaging
    /// brings the Director straight back to the same thread state.
    func returnToDashboard() {
        viewMode = .dashboard
    }
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
                guard let self else { return }
                self.partialTranscript = ""
                self.voiceOriginatedTurn = true
                // Dispatch: if a pop-out window has claimed voice, send the
                // transcript to its handler. Otherwise default to the main
                // thread's chat.
                if let handler = self.voiceTranscriptHandler {
                    handler(text)
                } else {
                    await self.send(text)
                }
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
                guard let self,
                      self.fluidListening,
                      !self.userMuted     // skip auto-resume while user is muted
                else { return }
                self.startListening()
            }
        }
        voice.onBargeIn = { [weak self] in
            // Director made noise while Eve was mid-reply. Per Director's
            // spec: this means "stop talking, I want to move on" — NOT
            // "I'm about to dictate something." So we just go idle. The
            // text of Eve's reply is preserved in the chat; if Director
            // wants to actually speak they hit the mic explicitly.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eveStatus = .idle
                self.partialTranscript = ""
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

    /// Called by `LumenAuthRegistry` when the active user changes. Drops every
    /// per-user surface so the next render shows the incoming user's context,
    /// then re-fetches the dashboard + briefing under the new identity.
    ///
    /// Why this matters: without this hook, switching from Patrick to Londynn
    /// would leave Patrick's conversations, operations, and briefing visible
    /// — a privacy-violating data leak. By re-baselining at switch time the
    /// UI is always scoped to the cookie that's currently in flight.
    func reloadForActiveUserSwitch() {
        // Per-user state — clear everything tied to identity
        messages = []
        conversations = []
        agents = []
        operations = []
        directives = []
        memories = []
        briefingDelta = nil
        currentConversationId = nil
        currentConversationTitle = nil
        loadedHistory = []
        loadedHistoryTitle = nil
        partialTranscript = ""
        replyTarget = nil
        viewMode = .dashboard

        // Refetch under the new cookie
        Task {
            await fetchDashboard()
            await fetchOperations()
            await fetchBriefingDelta()
        }
    }

    // MARK: - Dashboard (nexus-web)

    @Published var briefingDelta: BriefingDelta? = nil
    @Published var briefingLoading: Bool = false
    private static let lastBriefingKey = "lumen.lastBriefingFetchedAt"

    /// Fetch the "what changed since last visit" delta from /api/eve/briefing.
    /// Uses the timestamp from the previous fetch as `since` so each visit
    /// shows only what's new since the last time the Director opened the
    /// briefing dashboard. Falls back to the past 24h on first run.
    func fetchBriefingDelta() async {
        let base = LumenAPIManager.shared.nexusBase
        let storedSince = UserDefaults.standard.string(forKey: Self.lastBriefingKey)
        var url = URL(string: "\(base)/api/eve/briefing")!
        if let s = storedSince {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "since", value: s)]
            url = comps.url ?? url
        }

        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }

        briefingLoading = true
        defer { briefingLoading = false }

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let isoF = ISO8601DateFormatter()
        isoF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parseDate: (String?) -> Date = { s in
            guard let s else { return .distantPast }
            return isoF.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? .distantPast
        }

        let stats  = json["stats"] as? [String: Any] ?? [:]
        let deltaJ = json["delta"] as? [String: Any] ?? [:]
        let now    = parseDate(json["now"] as? String)

        var delta = BriefingDelta.empty
        delta.since           = parseDate(json["since"] as? String)
        delta.fetchedAt       = now
        delta.activeOps       = stats["activeOps"] as? Int ?? 0
        delta.activeAgents    = stats["activeAgents"] as? Int ?? 0
        delta.activeDirectives = stats["activeDirectives"] as? Int ?? 0
        delta.memories        = stats["memories"] as? Int ?? 0

        delta.newOperations = (deltaJ["newOperations"] as? [[String: Any]] ?? []).map { d in
            BriefingOpItem(
                id: d["id"] as? String ?? "",
                label: d["label"] as? String ?? (d["name"] as? String ?? "Untitled"),
                status: d["status"] as? String ?? "",
                priority: d["priority"] as? String ?? ""
            )
        }
        delta.statusChangedOperations = (deltaJ["statusChangedOperations"] as? [[String: Any]] ?? []).map { d in
            BriefingOpItem(
                id: d["id"] as? String ?? "",
                label: d["label"] as? String ?? "Untitled",
                status: d["status"] as? String ?? "",
                priority: d["priority"] as? String ?? ""
            )
        }
        delta.newRecords = (deltaJ["newRecords"] as? [[String: Any]] ?? []).map { d in
            BriefingRecordItem(
                id: d["id"] as? String ?? "",
                title: d["title"] as? String ?? "Untitled",
                type: d["type"] as? String ?? "note",
                operationLabel: d["operationLabel"] as? String ?? ""
            )
        }
        let findings = deltaJ["findings"] as? [String: Any] ?? [:]
        delta.findingTotal = findings["totalCount"] as? Int ?? 0
        if let perAgent = findings["perAgent"] as? [String: Int] {
            delta.findingsPerAgent = perAgent.map { ($0.key, $0.value) }
                .sorted { $0.count > $1.count }
        }
        delta.completedResearch = (deltaJ["completedResearch"] as? [[String: Any]] ?? []).map { d in
            BriefingResearchItem(
                id: d["id"] as? String ?? "",
                operationLabel: d["operationLabel"] as? String ?? "",
                summary: d["summary"] as? String ?? ""
            )
        }

        briefingDelta = delta

        // Save the fetch timestamp so the next briefing fetch shows only what's
        // changed since this moment.
        UserDefaults.standard.set(json["now"] as? String, forKey: Self.lastBriefingKey)
    }

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

        // Dock badge: show count of active operations + agents so the user
        // sees system pulse at a glance without opening Lumen.
        refreshDockBadge()

        // Mirror dashboard agents/operations into LumenLocalDB so the next
        // cold start paints from cache instead of waiting on the network.
        // We piggyback on the existing dashboard fetch — no extra API call.
        if let rawAgents = json["agents"] as? [[String: Any]] {
            let cacheAgents: [LumenLocalDB.AgentRow] = rawAgents.compactMap { d in
                guard let id = d["id"] as? String,
                      let userId = d["user_id"] as? String,
                      let name = d["name"] as? String,
                      let updatedAt = (d["updated_at"] as? String) ?? (d["created_at"] as? String) else { return nil }
                return LumenLocalDB.AgentRow(
                    id: id, userId: userId, name: name,
                    codename: d["codename"] as? String,
                    role: d["role"] as? String ?? "analyst",
                    status: d["status"] as? String ?? "standby",
                    totalFindings: d["total_findings"] as? Int ?? 0,
                    lastScannedAt: d["last_scanned_at"] as? String,
                    createdAt: d["created_at"] as? String ?? updatedAt,
                    updatedAt: updatedAt
                )
            }
            await LumenLocalDB.shared.upsertAgents(cacheAgents)
        }
        if let rawOps = json["operations"] as? [[String: Any]] {
            let cacheOps: [LumenLocalDB.OperationRow] = rawOps.compactMap { d in
                guard let id = d["id"] as? String,
                      let userId = d["user_id"] as? String,
                      let name = d["name"] as? String,
                      let updatedAt = d["updated_at"] as? String else { return nil }
                return LumenLocalDB.OperationRow(
                    id: id, userId: userId, name: name,
                    codename: d["codename"] as? String,
                    status: d["status"] as? String ?? "active",
                    priority: d["priority"] as? String ?? "medium",
                    description: d["description"] as? String,
                    directives: d["directives"] as? String,
                    updatedAt: updatedAt,
                    createdAt: d["created_at"] as? String ?? updatedAt
                )
            }
            await LumenLocalDB.shared.upsertOperations(cacheOps)
        }
    }

    /// Update the macOS Dock tile badge with the count of active items.
    /// Called after dashboard refreshes; keeps the OS surface in sync with
    /// in-app state so the Director sees the pulse from anywhere.
    func refreshDockBadge() {
        let activeOps = operations.filter { $0.status.lowercased() == "active" }.count
        let activeAgents = agents.filter { $0.status.lowercased() == "active" }.count
        let total = activeOps + activeAgents
        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
        }
        diffAndNotify()
    }

    // MARK: - macOS notifications
    //
    // Diff agent findings + operation status across refreshes. When something
    // new appears, post a system notification so the Director gets the signal
    // even when Lumen is minimized.

    private var lastFindingCounts: [String: Int] = [:]   // agentId -> total_findings
    private var lastOpStatuses: [String: String] = [:]   // operationId -> status
    private var notificationsAuthorized: Bool = false
    private var notificationsRequested: Bool = false

    private func diffAndNotify() {
        // Lazy permission request on first refresh that has data.
        if !notificationsRequested {
            notificationsRequested = true
            requestNotificationAuth()
        }

        // Agent findings deltas
        for agent in agents {
            let prev = lastFindingCounts[agent.agentId]
            if let prev, agent.totalFindings > prev {
                let delta = agent.totalFindings - prev
                postNotification(
                    title: "\(agent.name) surfaced \(delta) new finding\(delta == 1 ? "" : "s")",
                    body: agent.role,
                    identifier: "agent-\(agent.agentId)-\(agent.totalFindings)"
                )
            }
            lastFindingCounts[agent.agentId] = agent.totalFindings
        }

        // Operation status changes
        for op in operations {
            let prev = lastOpStatuses[op.operationId]
            if let prev, prev != op.status {
                postNotification(
                    title: "Operation \(op.codename.isEmpty ? op.name : op.codename): \(op.status.uppercased())",
                    body: "Status changed from \(prev) → \(op.status)",
                    identifier: "op-\(op.operationId)-\(op.status)"
                )
            }
            lastOpStatuses[op.operationId] = op.status
        }
    }

    private func requestNotificationAuth() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.notificationsAuthorized = granted
            }
        }
    }

    private func postNotification(title: String, body: String, identifier: String) {
        guard notificationsAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func fetchOperations() async {
        // Cache-first paint from LumenLocalDB so the Operations panel never
        // shows a blank list during the network round-trip. The cached rows
        // only have the canonical columns (no nested `agents`/`records`),
        // so we reconstruct the flat dict + structured array from them and
        // let the remote fetch enrich on top.
        let cached = await LumenLocalDB.shared.fetchOperations(limit: 200)
        if !cached.isEmpty && operations.isEmpty {
            let cachedRaw: [[String: Any]] = cached.map { row in
                var d: [String: Any] = [
                    "id": row.id,
                    "user_id": row.userId,
                    "name": row.name,
                    "status": row.status,
                    "priority": row.priority,
                    "updated_at": row.updatedAt,
                    "created_at": row.createdAt,
                ]
                if let cn = row.codename { d["codename"] = cn }
                if let dsc = row.description { d["description"] = dsc }
                if let dir = row.directives { d["directives"] = dir }
                return d
            }
            operationRecords = Dictionary(
                uniqueKeysWithValues: cachedRaw.compactMap { dict in
                    guard let id = dict["id"] as? String else { return nil }
                    return (id, flatten(dict))
                }
            )
            operations = makeOperations(from: cachedRaw)
        }

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

        // Mirror to local cache so the next cold start paints with real data
        // instead of waiting for the network. We only persist the canonical
        // columns — nested `records` / `agents` collections live on their
        // own rows in the cache.
        let cacheRows: [LumenLocalDB.OperationRow] = rawOps.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let name = d["name"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.OperationRow(
                id: id, userId: userId, name: name,
                codename: d["codename"] as? String,
                status: d["status"] as? String ?? "active",
                priority: d["priority"] as? String ?? "medium",
                description: d["description"] as? String,
                directives: d["directives"] as? String,
                updatedAt: updatedAt,
                createdAt: d["created_at"] as? String ?? updatedAt
            )
        }
        await LumenLocalDB.shared.upsertOperations(cacheRows)
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
        // Cache-first paint, then refresh from nexus-web. If the network
        // never responds we keep the cache; the sync engine will refill.
        let cached = await LumenLocalDB.shared.fetchDirectives()
        if !cached.isEmpty {
            directives = cached.map { row in
                DirectiveItem(
                    id: row.id, type: row.type, title: row.title, content: row.content,
                    priority: row.priority, target: row.target ?? "all", isActive: row.isActive
                )
            }
        }

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

        // Mirror to local cache for next cold start
        let cacheRows: [LumenLocalDB.DirectiveRow] = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let type = d["type"] as? String,
                  let title = d["title"] as? String,
                  let content = d["content"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.DirectiveRow(
                id: id, userId: userId, type: type, title: title, content: content,
                isActive: d["is_active"] as? Bool ?? true,
                priority: d["priority"] as? Int ?? 0,
                target: d["target"] as? String,
                updatedAt: updatedAt
            )
        }
        await LumenLocalDB.shared.upsertDirectives(cacheRows)
    }

    func fetchMemories() async {
        // Cache-first paint, then refresh from nexus-web.
        let cached = await LumenLocalDB.shared.fetchMemories()
        if !cached.isEmpty {
            memories = cached.map { row in
                MemoryItem(
                    id: row.id, type: row.type, content: row.content,
                    priority: row.priority, source: row.source ?? "manual",
                    updatedAt: row.updatedAt
                )
            }
        }

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

        // Mirror to local cache
        let cacheRows: [LumenLocalDB.MemoryRow] = raw.compactMap { m in
            guard let id = m["id"] as? String,
                  let userId = m["user_id"] as? String,
                  let type = m["type"] as? String,
                  let content = m["content"] as? String,
                  let updatedAt = m["updated_at"] as? String else { return nil }
            return LumenLocalDB.MemoryRow(
                id: id, userId: userId, type: type, content: content,
                source: m["source"] as? String,
                isActive: m["is_active"] as? Bool ?? true,
                priority: m["priority"] as? Int ?? 5,
                updatedAt: updatedAt
            )
        }
        await LumenLocalDB.shared.upsertMemories(cacheRows)
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

    /// Search every thread (titles + message content) by hitting
    /// /api/eve/search?q=<query>. Returns conversation hits sorted by
    /// relevance (title matches first, then most-recent content).
    func crossThreadSearch(query: String) async -> [CrossThreadSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let base = LumenAPIManager.shared.nexusBase
        guard var comps = URLComponents(string: "\(base)/api/eve/search") else { return [] }
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["results"] as? [[String: Any]]
        else { return [] }

        return raw.compactMap { d in
            guard let cid = d["conversation_id"] as? String else { return nil }
            return CrossThreadSearchHit(
                id: cid,
                conversationId: cid,
                title:     (d["title"]   as? String) ?? "Untitled",
                source:    (d["source"]  as? String) ?? "",
                snippet:   (d["snippet"] as? String) ?? "",
                matchType: (d["matchType"] as? String) ?? "content"
            )
        }
    }

    func fetchConversations() async {
        // Cache-first: paint from LumenLocalDB immediately so the panel
        // doesn't blank-spinner on every navigation. Then hit nexus-web for
        // the enriched list (preview + count) and replace if it returns.
        // If the network is dead we keep the local view and the sync engine
        // will catch up in the background.
        let cached = await LumenLocalDB.shared.fetchConversations(limit: 60)
        if !cached.isEmpty {
            conversations = cached.map { row in
                ConversationSummary(
                    id: row.id,
                    title: row.title,
                    source: row.source,
                    updatedAt: parseTimestamp(row.updatedAt),
                    preview: row.preview,
                    messageCount: row.messageCount
                )
            }
        }

        // Prefer nexus-web's /api/eve/conversations — returns preview + count.
        // Falls back to direct Supabase REST if nexus-web is unreachable.
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/conversations") else {
            // Network unreachable — keep cached view if we had one, else try
            // direct Supabase as a last resort.
            if cached.isEmpty {
                conversations = await SupabaseClient.shared.fetchConversations()
            }
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
            // Remote failed — cached view stays, fall back only when there
            // was nothing to paint at all.
            if cached.isEmpty {
                conversations = await SupabaseClient.shared.fetchConversations()
            }
            return
        }
        let fresh: [ConversationSummary] = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let title = d["title"] as? String else { return nil }
            let upd = d["updated_at"] as? String ?? ""
            return ConversationSummary(
                id: id,
                title: title,
                source: d["source"] as? String ?? "lumen",
                updatedAt: parseTimestamp(upd),
                preview: d["preview"] as? String ?? "",
                messageCount: d["message_count"] as? Int ?? 0
            )
        }
        conversations = fresh

        // Mirror enriched rows into the local cache so the next cold start
        // paints with preview + count, not the bare title-only fallback.
        let cacheRows: [LumenLocalDB.ConversationRow] = raw.compactMap { d in
            guard let id = d["id"] as? String,
                  let title = d["title"] as? String,
                  let upd = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.ConversationRow(
                id: id,
                userId: "e9d9a15b-0e5a-4631-9b50-6225ee03a44f",
                title: title,
                source: d["source"] as? String ?? "lumen",
                createdAt: d["created_at"] as? String ?? upd,
                updatedAt: upd,
                preview: d["preview"] as? String ?? "",
                messageCount: d["message_count"] as? Int ?? 0
            )
        }
        await LumenLocalDB.shared.upsertConversations(cacheRows)
    }

    /// Parse a Postgres ISO timestamp (with or without fractional seconds)
    /// into a Date. Returns distantPast on failure so sort order doesn't blow up.
    private func parseTimestamp(_ s: String) -> Date {
        struct F {
            static let full: ISO8601DateFormatter = {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }()
            static let basic = ISO8601DateFormatter()
        }
        return F.full.date(from: s) ?? F.basic.date(from: s) ?? Date.distantPast
    }

    func loadConversation(id: String, title: String) async {
        // Cache-first: paint the previously-cached transcript so the panel
        // opens instantly even on slow networks. Then re-fetch from Supabase
        // and replace if it returns. If the network is dead the cached
        // messages stay — full offline conversation viewing.
        currentConversationId = id
        currentConversationTitle = title
        loadedHistory = []
        loadedHistoryTitle = nil
        lastError = nil

        let cached = await LumenLocalDB.shared.fetchMessages(conversationId: id)
        if !cached.isEmpty {
            messages = cached.map { row in
                ChatMessage(role: row.role == "user" ? .user : .assistant, content: row.content)
            }
            titleGenerated = cached.count >= 6
        }

        let msgs = await SupabaseClient.shared.fetchMessages(conversationId: id)
        if !msgs.isEmpty {
            messages = msgs
            titleGenerated = msgs.count >= 6
            // Mirror to the SQLite cache for next cold open. Single-conversation
            // overwrite — small enough to be cheap.
            let rows = msgs.map { msg in
                LumenLocalDB.MessageRow(
                    role: msg.role == .user ? "user" : "assistant",
                    content: msg.content,
                    createdAt: nil
                )
            }
            await LumenLocalDB.shared.replaceMessages(conversationId: id, messages: rows)
        }

        // Keep the legacy session_cache.json path alive for the floating
        // window's "last open" hint until that surface is migrated too.
        SupabaseClient.shared.cacheSession(conversationId: id, messages: messages)
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

    /// Replace a user message and re-fetch a reply. Truncates the visible
    /// thread back to the edited message, then sends the new text — Eve
    /// answers fresh against the prior context (everything before the edit).
    /// DB rows for the dropped turns are not deleted; they remain in
    /// eve_history but the local thread is what the user sees.
    func regenerate(fromUserMessageId id: UUID, newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        // Drop the original user turn AND everything that came after.
        messages.removeSubrange(idx..<messages.count)
        await send(trimmed)
    }

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

            // Voice-originated turns prefer local for fluidity. Typed turns
            // honor the global preference. Reset the flag immediately so the
            // next typed turn doesn't accidentally inherit it.
            let preferLocalThisTurn = preferLocalBrain || voiceOriginatedTurn
            voiceOriginatedTurn = false

            if preferLocalThisTurn {
                // Local-primary path — full streaming, no tool calls.
                messages.append(ChatMessage(role: .assistant, content: "", brain: "local"))
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

            var capturedToolCalls: [ToolCallSummary] = []
            do {
                // Streaming Grok — Eve appears word-by-word, tool cards land as
                // they execute. Insert placeholder we mutate as deltas arrive.
                messages.append(ChatMessage(role: .assistant, content: "", brain: "grok"))
                let streamIdx = messages.count - 1
                eveStatus = .speaking

                let result = try await api.callNexusEveStreaming(
                    message: text,
                    conversationId: currentConversationId,
                    history: messages.dropFirst().dropLast(),
                    onChunk: { [weak self] delta in
                        guard let self else { return }
                        guard streamIdx < self.messages.count else { return }
                        self.messages[streamIdx].content += delta
                    },
                    onToolCall: { [weak self] summary in
                        guard let self else { return }
                        guard streamIdx < self.messages.count else { return }
                        self.messages[streamIdx].toolCalls.append(summary)
                    }
                )
                response    = result.content
                nexusConvId = result.conversationId
                capturedToolCalls = result.toolCalls
                // Final pass — make sure content matches done event exactly
                if streamIdx < messages.count {
                    messages[streamIdx].content = result.content
                }
                if let newId = nexusConvId, currentConversationId == nil {
                    currentConversationId = newId
                }
                if currentConversationTitle == nil {
                    currentConversationTitle = String(text.prefix(60))
                }
                speak(response)
                eveStatus = .idle
                let snapshot = messages
                Task {
                    let convId = await ensureConversation(firstMessage: text)
                    SupabaseClient.shared.cacheSession(conversationId: convId, messages: snapshot)
                    await maybeGenerateTitle(conversationId: convId, history: snapshot)
                }
                return
            } catch {
                // Streaming failed — drop the placeholder we appended above.
                if !messages.isEmpty, messages.last?.role == .assistant, messages.last?.content == "" {
                    messages.removeLast()
                }
                // Nexus-web unavailable — stream from local Ollama so Eve text
                // appears token-by-token. Fall back to Claude only if Ollama
                // also fails. Insert a placeholder we mutate as deltas arrive.
                messages.append(ChatMessage(role: .assistant, content: "", brain: "local"))
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
                    messages.append(ChatMessage(role: .assistant, content: response, brain: "claude"))
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

            var assistantMsg = ChatMessage(role: .assistant, content: response, brain: "grok")
            assistantMsg.toolCalls = capturedToolCalls
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
            messages.append(ChatMessage(role: .assistant, content: errMsg, brain: "offline"))
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
            messages.append(ChatMessage(role: .assistant, content: result.content, brain: "vision"))
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

    // Returns existing conversationId or creates a new one. Optimistic:
    // the id is generated locally and the conversation lands in the cache
    // + UI immediately. The server-side create runs in the background; if
    // it fails, the row is still on the user's machine and the next sync
    // pass will reconcile.
    private func ensureConversation(firstMessage: String) async -> String {
        if let id = currentConversationId { return id }

        let title    = String(firstMessage.prefix(60))
        let newId    = UUID().uuidString.lowercased()
        let nowIso   = isoNowString()
        let userId   = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"  // TODO: pull from active human when Lumen goes multi-user

        // Optimistic local insert — appears in cache immediately so the
        // conversation list updates without waiting on the network.
        await LumenLocalDB.shared.upsertConversations([
            LumenLocalDB.ConversationRow(
                id: newId, userId: userId, title: title, source: "lumen",
                createdAt: nowIso, updatedAt: nowIso,
                preview: "", messageCount: 0
            )
        ])

        await MainActor.run {
            currentConversationId = newId
            currentConversationTitle = title
            // Splice into the in-memory list so the UI refreshes without a
            // full fetchConversations round-trip. Newest first ordering.
            let summary = ConversationSummary(
                id: newId, title: title, source: "lumen",
                updatedAt: Date(), preview: "", messageCount: 0
            )
            self.conversations.insert(summary, at: 0)
        }

        // Server-side create in the background. We pass the explicit id so
        // the server row has the same primary key — no after-the-fact swap.
        // If the network call fails (offline, server down), flag the row so
        // LumenSyncEngine retries it on the next pass instead of leaving an
        // orphan in the local cache that never makes it to Supabase.
        Task.detached {
            let result = await SupabaseClient.shared.createConversation(title: title, explicitId: newId)
            if result == nil {
                await LumenLocalDB.shared.markConversationPendingSync(id: newId, pending: true)
            }
        }

        return newId
    }

    /// Helper for synthesizing ISO timestamps when we mint rows locally.
    private func isoNowString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    // MARK: - Voice

    func speak(_ text: String) {
        voice.speak(text) { [weak self] in
            Task { @MainActor [weak self] in self?.eveStatus = .idle }
        }
    }

    func startListening() {
        // Backward-compatible entry — main thread claims voice with no
        // custom handler (transcripts go through the regular send() path).
        startVoiceFor(claimId: "main", handler: nil)
    }

    /// Generic claim API. Any surface (main thread, ConversationWindow,
    /// QuickCapture, etc.) calls this with its own claimId + an optional
    /// transcript handler. While the claim is held, the mic only routes
    /// transcripts to that surface.
    /// - Parameter claimId: stable identifier for the surface (use "main"
    ///   or the conversationId for pop-outs).
    /// - Parameter handler: nil means "use the main thread's send()".
    func startVoiceFor(claimId: String, handler: ((String) -> Void)?) {
        voiceClaimedBy        = claimId
        voiceTranscriptHandler = handler
        fluidListening        = true
        userMuted             = false
        eveStatus             = .listening
        partialTranscript     = ""
        voice.bargeInEnabled  = true
        voice.startListening()
    }

    func stopListening() {
        fluidListening = false
        userMuted = false
        voiceClaimedBy = nil
        voiceTranscriptHandler = nil
        voice.stopListening()
        voice.bargeInEnabled = false
        if eveStatus == .listening { eveStatus = .idle }
    }

    /// Toggle the user's mute within an active voice session. Mute stops the
    /// recognizer + suppresses barge-in so Director can let Eve finish
    /// uninterrupted. Unmute resumes listening if Eve is idle (or queues for
    /// the next ready-to-listen trigger if she's still speaking).
    func toggleUserMute() {
        userMuted.toggle()
        voice.bargeInEnabled = !userMuted
        if userMuted {
            // Pull the mic. If Eve is talking, this also suppresses barge-in
            // (already handled via bargeInEnabled).
            voice.stopListening()
            partialTranscript = ""
            if eveStatus == .listening { eveStatus = .idle }
        } else {
            // Unmuted — if session is alive AND Eve isn't currently speaking,
            // resume listening immediately. Otherwise the next onReadyToListen
            // (after Eve finishes) will pick it up automatically.
            if fluidListening, eveStatus != .speaking, eveStatus != .thinking {
                voice.startListening()
                eveStatus = .listening
            }
        }
    }
}
