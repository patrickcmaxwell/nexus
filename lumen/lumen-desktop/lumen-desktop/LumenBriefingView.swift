import SwiftUI

// LumenBriefingView
//
// Surface for nexus-web's /api/eve/briefing endpoint — Eve's "what's
// changed since you were last here" view. Pulls new ops, status changes,
// new records, recent agent findings, and completed research jobs.
//
// Lives in the Console as the "Today" tab so users have a single place to
// glance at what's been moving without opening every panel. The endpoint
// already exists and is shipping data; this is the missing UI surface.

struct LumenBriefingView: View {
    @State private var briefing: Briefing? = nil
    @State private var isLoading: Bool = false
    @State private var error: String? = nil
    @State private var loadedAt: Date? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if isLoading && briefing == nil {
                    loadingState
                } else if let briefing {
                    statsRow(briefing)
                    if !briefing.newOperations.isEmpty {
                        section("NEW OPERATIONS", count: briefing.newOperations.count) {
                            ForEach(briefing.newOperations) { item in
                                opRow(item)
                            }
                        }
                    }
                    if !briefing.statusChangedOperations.isEmpty {
                        section("STATUS CHANGED", count: briefing.statusChangedOperations.count) {
                            ForEach(briefing.statusChangedOperations) { item in
                                opRow(item, isStatusChange: true)
                            }
                        }
                    }
                    if !briefing.newRecords.isEmpty {
                        section("NEW RECORDS", count: briefing.newRecords.count) {
                            ForEach(briefing.newRecords) { item in
                                recordRow(item)
                            }
                        }
                    }
                    if !briefing.completedResearch.isEmpty {
                        section("RESEARCH COMPLETED", count: briefing.completedResearch.count) {
                            ForEach(briefing.completedResearch) { item in
                                researchRow(item)
                            }
                        }
                    }
                    if !briefing.findingsLatest.isEmpty {
                        section("AGENT FINDINGS", count: briefing.findingsTotalCount) {
                            ForEach(briefing.findingsLatest) { item in
                                findingRow(item)
                            }
                        }
                    }
                    if briefing.isQuiet {
                        Text("Nothing new in the last 24 hours.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.top, 8)
                    }
                } else if let error {
                    errorState(error)
                }
            }
            .padding(24)
        }
        .onAppear { if briefing == nil { reload() } }
    }

    // MARK: - Header / sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.cyanAccent)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.cyanAccent, radius: 4)
                    Text("TODAY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color.cyanAccent.opacity(0.95))
                }
                Text("What's moved since 24 hours ago — pulled from /api/eve/briefing")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button(action: reload) {
                HStack(spacing: 6) {
                    if isLoading { ProgressView().controlSize(.small).tint(Color.cyanAccent) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold)) }
                    Text(isLoading ? "REFRESHING" : "REFRESH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(Color.cyanAccent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Color.cyanAccent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5).stroke(Color.cyanAccent.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Color.cyanAccent)
            Text("Fetching today's brief…")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color.redAccent)
                Text("Could not load briefing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.redAccent)
            }
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(14)
        .background(Color.redAccent.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.redAccent.opacity(0.3), lineWidth: 1)
        )
    }

    private func statsRow(_ b: Briefing) -> some View {
        HStack(spacing: 10) {
            statTile("ACTIVE OPS",   value: b.stats.activeOps,        color: Color.cyanAccent)
            statTile("ACTIVE AGENTS", value: b.stats.activeAgents,    color: Color(.sRGB, red: 0.65, green: 0.45, blue: 0.95, opacity: 1))
            statTile("DIRECTIVES",   value: b.stats.activeDirectives, color: Color(.sRGB, red: 0.95, green: 0.45, blue: 0.65, opacity: 1))
            statTile("MEMORIES",     value: b.stats.memories,         color: Color(.sRGB, red: 0.45, green: 0.85, blue: 0.65, opacity: 1))
        }
    }

    private func statTile(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.5))
                Text("· \(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.cyanAccent.opacity(0.7))
                Spacer()
            }
            VStack(spacing: 1) { content() }
        }
    }

    // MARK: - Rows

    private func opRow(_ item: BriefingOp, isStatusChange: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(item.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            statusPill(item.status)
            if let pri = item.priority { priorityPill(pri) }
            Spacer()
            if let date = isStatusChange ? item.updatedAt : item.createdAt {
                Text(relativeTime(date))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.025))
    }

    private func recordRow(_ item: BriefingRecord) -> some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            Text(item.type.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            if !item.operationLabel.isEmpty {
                Text("· \(item.operationLabel)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            if let date = item.createdAt {
                Text(relativeTime(date))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.025))
    }

    private func researchRow(_ item: BriefingResearch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.operationLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                if let date = item.completedAt {
                    Text(relativeTime(date))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
    }

    private func findingRow(_ item: BriefingFinding) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                Text("by \(item.agent)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            if let date = item.createdAt {
                Text(relativeTime(date))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.025))
    }

    // MARK: - Pills

    private func statusPill(_ status: String) -> some View {
        let c: Color = {
            switch status.lowercased() {
            case "active":    return Color.greenAccent
            case "paused":    return Color(.sRGB, red: 0.95, green: 0.78, blue: 0.30, opacity: 1)
            case "complete", "completed": return Color.cyanAccent.opacity(0.7)
            default:          return .white.opacity(0.45)
            }
        }()
        return Text(status.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(c)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(c.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(c.opacity(0.4), lineWidth: 1)
            )
    }

    private func priorityPill(_ priority: String) -> some View {
        let c: Color = {
            switch priority.lowercased() {
            case "critical":  return Color.redAccent
            case "high":      return Color(.sRGB, red: 0.95, green: 0.55, blue: 0.30, opacity: 1)
            default:          return .white.opacity(0.4)
            }
        }()
        return Text(priority.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(c)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(c.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(c.opacity(0.4), lineWidth: 1)
            )
    }

    // MARK: - Loader

    private func reload() {
        isLoading = true
        error = nil
        Task {
            let result = await fetchBriefing()
            await MainActor.run {
                self.briefing = result.brief
                self.error = result.error
                self.isLoading = false
                self.loadedAt = Date()
            }
        }
    }

    private func fetchBriefing() async -> (brief: Briefing?, error: String?) {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/eve/briefing") else {
            return (nil, "Bad URL")
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return (nil, "HTTP \(code)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, "Bad JSON")
            }
            return (Briefing(json: json), nil)
        } catch {
            return (nil, (error as NSError).localizedDescription)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60   { return "JUST NOW" }
        if s < 3600 { return "\(Int(s / 60))M AGO" }
        if s < 86400 { return "\(Int(s / 3600))H AGO" }
        return "\(Int(s / 86400))D AGO"
    }
}

// MARK: - Briefing model

struct Briefing {
    let stats: Stats
    let newOperations: [BriefingOp]
    let statusChangedOperations: [BriefingOp]
    let newRecords: [BriefingRecord]
    let findingsLatest: [BriefingFinding]
    let findingsTotalCount: Int
    let completedResearch: [BriefingResearch]

    struct Stats {
        let activeOps: Int
        let activeAgents: Int
        let activeDirectives: Int
        let memories: Int
    }

    var isQuiet: Bool {
        newOperations.isEmpty && statusChangedOperations.isEmpty &&
        newRecords.isEmpty && findingsLatest.isEmpty && completedResearch.isEmpty
    }

    init(json: [String: Any]) {
        let s = json["stats"] as? [String: Any] ?? [:]
        self.stats = Stats(
            activeOps:        s["activeOps"]        as? Int ?? 0,
            activeAgents:     s["activeAgents"]     as? Int ?? 0,
            activeDirectives: s["activeDirectives"] as? Int ?? 0,
            memories:         s["memories"]         as? Int ?? 0
        )
        let delta = json["delta"] as? [String: Any] ?? [:]
        self.newOperations = (delta["newOperations"] as? [[String: Any]] ?? []).map(BriefingOp.init)
        self.statusChangedOperations = (delta["statusChangedOperations"] as? [[String: Any]] ?? []).map(BriefingOp.init)
        self.newRecords = (delta["newRecords"] as? [[String: Any]] ?? []).map(BriefingRecord.init)
        self.completedResearch = (delta["completedResearch"] as? [[String: Any]] ?? []).map(BriefingResearch.init)

        let findings = delta["findings"] as? [String: Any] ?? [:]
        self.findingsTotalCount = findings["totalCount"] as? Int ?? 0
        self.findingsLatest = (findings["latest"] as? [[String: Any]] ?? []).map(BriefingFinding.init)
    }
}

struct BriefingOp: Identifiable {
    let id: String
    let label: String
    let status: String
    let priority: String?
    let createdAt: Date?
    let updatedAt: Date?
    init(_ d: [String: Any]) {
        self.id = (d["id"] as? String) ?? UUID().uuidString
        self.label = (d["label"] as? String) ?? (d["name"] as? String) ?? "Untitled"
        self.status = (d["status"] as? String) ?? "active"
        self.priority = d["priority"] as? String
        self.createdAt = (d["createdAt"] as? String).flatMap(parseISO)
        self.updatedAt = (d["updatedAt"] as? String).flatMap(parseISO)
    }
}

struct BriefingRecord: Identifiable {
    let id: String
    let title: String
    let type: String
    let operationLabel: String
    let createdAt: Date?
    init(_ d: [String: Any]) {
        self.id = (d["id"] as? String) ?? UUID().uuidString
        self.title = (d["title"] as? String) ?? "Untitled"
        self.type = (d["type"] as? String) ?? "note"
        self.operationLabel = (d["operationLabel"] as? String) ?? ""
        self.createdAt = (d["createdAt"] as? String).flatMap(parseISO)
    }
}

struct BriefingResearch: Identifiable {
    let id: String
    let operationLabel: String
    let summary: String
    let completedAt: Date?
    init(_ d: [String: Any]) {
        self.id = (d["id"] as? String) ?? UUID().uuidString
        self.operationLabel = (d["operationLabel"] as? String) ?? "Operation"
        self.summary = (d["summary"] as? String) ?? ""
        self.completedAt = (d["completedAt"] as? String).flatMap(parseISO)
    }
}

struct BriefingFinding: Identifiable {
    let id = UUID().uuidString
    let agent: String
    let summary: String
    let createdAt: Date?
    init(_ d: [String: Any]) {
        self.agent = (d["agent"] as? String) ?? "Agent"
        self.summary = (d["summary"] as? String) ?? ""
        self.createdAt = (d["createdAt"] as? String).flatMap(parseISO)
    }
}

private func parseISO(_ s: String) -> Date? {
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f1.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
