import SwiftUI
import AppKit

// LumenArenaView
//
// Console tab that surfaces Arena (the executor) inside Lumen so users
// don't have to bounce to a browser to see what Eve has been doing. Read-
// only by design — connection management still happens at arena-web,
// reachable via the "Manage in browser" button.
//
// Pulls from two nexus-web endpoints:
//   /api/arena/connections — per-user connection list + provider catalog
//   /api/arena/log         — recent audit log rows
//
// Both ride the existing session cookie, so no extra auth wiring is
// needed today. Once cross-subdomain cookies land we could swap to
// arena-web direct, but the current setup works without DNS.

struct LumenArenaView: View {
    @State private var connections: [Connection] = []
    @State private var providers: [Provider] = []
    @State private var actions: [ActionRow] = []
    @State private var manageUrl: String = "https://arena-web-green.vercel.app/dashboard"
    @State private var loading: Bool = true
    @State private var refreshing: Bool = false
    @State private var error: String? = nil
    @State private var actionFilter: String = "all"

    struct Connection: Identifiable, Decodable {
        let id: String
        let provider: String
        let label: String?
        let status: String
        let last_used_at: String?
        let last_error: String?
    }

    struct Provider: Identifiable, Decodable {
        let id: String
        let name: String
        let methods: [String]
    }

    struct ActionRow: Identifiable, Decodable {
        let id: String
        let action: String
        let caller: String?
        let status: String
        let result: [String: AnyCodable]?
        let error_msg: String?
        let created_at: String
    }

    /// Erased value to decode arbitrary JSON in `result`. Only `mocked` and
    /// `detail` matter for rendering, so we read those two and ignore the rest.
    struct AnyCodable: Decodable {
        let value: Any?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self)   { value = b; return }
            if let s = try? c.decode(String.self) { value = s; return }
            if let n = try? c.decode(Double.self) { value = n; return }
            value = nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let err = error { errorBox(err) }
                if loading && connections.isEmpty && actions.isEmpty {
                    loadingState
                } else {
                    statsRow
                    connectionsSection
                    Divider().background(Color.white.opacity(0.06))
                    actionsSection
                }
            }
            .padding(24)
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.cyanAccent)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.cyanAccent, radius: 4)
                    Text("ARENA")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color.cyanAccent.opacity(0.95))
                }
                Text("What Eve has done in the real world. Connections live in arena-web; this is the in-Lumen readout.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { Task { await refresh() } }) {
                    HStack(spacing: 6) {
                        if refreshing { ProgressView().controlSize(.small).tint(Color.cyanAccent) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold)) }
                        Text(refreshing ? "REFRESHING" : "REFRESH")
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
                .disabled(refreshing)

                Button(action: openInBrowser) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11, weight: .bold))
                        Text("MANAGE IN BROWSER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 8) {
            stat("CONNECTIONS",  value: connections.count,                  color: Color.cyanAccent)
            stat("PROVIDERS",    value: providers.count,                    color: Color.purpleAccent)
            stat("ACTIONS",      value: actions.count,                      color: Color.greenAccent)
            stat("ERRORS",       value: actions.filter { $0.status == "error" }.count, color: Color.redAccent)
        }
    }

    private func stat(_ label: String, value: Int, color: Color) -> some View {
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

    // MARK: Connections

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR CONNECTIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white.opacity(0.45))

            if providers.isEmpty {
                Text("Arena unreachable. Service may be down.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            } else if connections.isEmpty {
                emptyConnectionsCard
            } else {
                ForEach(providers) { provider in
                    let conns = connections.filter { $0.provider == provider.id }
                    providerRow(provider: provider, connections: conns)
                }
            }
        }
    }

    private var emptyConnectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No active connections.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Text("Eve's Arena calls run in safe-mock mode until you wire at least one. Click \"Manage in browser\" to add ClickUp, Notion, GitHub, Stripe, or Slack.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func providerRow(provider: Provider, connections: [Connection]) -> some View {
        let accent = providerAccent(provider.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(accent)
                Text(provider.methods.joined(separator: " · "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            if connections.isEmpty {
                Text("NOT CONNECTED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
            } else {
                ForEach(connections) { c in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(c.status == "active" ? Color.greenAccent : Color.redAccent)
                            .frame(width: 5, height: 5)
                        Text(c.label ?? "Default")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
        .overlay(
            Rectangle()
                .frame(width: 2)
                .foregroundColor(accent.opacity(connections.isEmpty ? 0 : 0.6)),
            alignment: .leading
        )
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ACTIONS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                actionFilterPicker
            }

            if visibleActions.isEmpty {
                Text("No matching actions.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.vertical, 12)
            } else {
                ForEach(visibleActions) { actionRow($0) }
            }
        }
    }

    private var actionFilterPicker: some View {
        HStack(spacing: 2) {
            ForEach(["all", "task", "payment", "sync"], id: \.self) { kind in
                Button(action: { actionFilter = kind }) {
                    Text(kind.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(actionFilter == kind ? Color.cyanAccent : .white.opacity(0.45))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(actionFilter == kind ? Color.cyanAccent.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var visibleActions: [ActionRow] {
        if actionFilter == "all" { return actions }
        return actions.filter { $0.action.hasPrefix(actionFilter) }
    }

    private func actionRow(_ action: ActionRow) -> some View {
        let mocked = (action.result?["mocked"]?.value as? Bool) == true
        let detail = action.result?["detail"]?.value as? String
        return HStack(spacing: 10) {
            Image(systemName: action.status == "success" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(action.status == "success" ? Color.greenAccent : Color.redAccent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.action.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.85))
                    if let caller = action.caller {
                        Text("via \(caller)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    if mocked {
                        Text("MOCKED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(Color.amberAccent)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3).stroke(Color.amberAccent.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                if let err = action.error_msg {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(Color.redAccent.opacity(0.85))
                        .lineLimit(2)
                } else if let d = detail {
                    Text(d)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(relativeTime(action.created_at))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.025))
    }

    // MARK: Loading + helpers

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(Color.cyanAccent)
            Text("Loading Arena state…")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.vertical, 24)
    }

    private func errorBox(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color.redAccent)
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(Color.redAccent.opacity(0.9))
        }
        .padding(10)
        .background(Color.redAccent.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.redAccent.opacity(0.3), lineWidth: 1)
        )
    }

    private func openInBrowser() {
        guard let url = URL(string: manageUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    private func load() async {
        loading = true
        await fetchAll()
        loading = false
    }

    private func refresh() async {
        refreshing = true
        await fetchAll()
        refreshing = false
    }

    private func fetchAll() async {
        error = nil
        let base = LumenAPIManager.shared.nexusBase

        async let connectionsTask = fetchConnections(base: base)
        async let actionsTask     = fetchActions(base: base)

        let (connResult, actionsResult) = await (connectionsTask, actionsTask)
        if let connResult {
            connections = connResult.connections
            providers = connResult.providers
            if !connResult.manage_url.isEmpty { manageUrl = connResult.manage_url }
            // Push the freshly-fetched count into the shared health singleton
            // so the Console tab picker can render a badge without re-fetching.
            LumenArenaHealth.shared.update(connections: connResult.connections)
        }
        if let actionsResult {
            actions = actionsResult
        }
        if connResult == nil && actionsResult == nil {
            error = "Couldn't reach Nexus. Check your connection."
        }
    }

    private struct ConnectionsPayload: Decodable {
        let connections: [Connection]
        let providers: [Provider]
        let manage_url: String
    }

    private func fetchConnections(base: String) async -> ConnectionsPayload? {
        guard let url = URL(string: "\(base)/api/arena/connections") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ConnectionsPayload.self, from: data)
        } catch { return nil }
    }

    private struct ActionsPayload: Decodable {
        let entries: [ActionRow]
    }

    private func fetchActions(base: String) async -> [ActionRow]? {
        guard let url = URL(string: "\(base)/api/arena/log?limit=50") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(ActionsPayload.self, from: data).entries
        } catch { return nil }
    }

    private func providerAccent(_ id: String) -> Color {
        switch id {
        case "clickup": return Color(.sRGB, red: 0.65, green: 0.45, blue: 0.95, opacity: 1)
        case "notion":  return Color(.sRGB, red: 0.92, green: 0.92, blue: 0.92, opacity: 1)
        case "github":  return Color(.sRGB, red: 0.85, green: 0.85, blue: 0.85, opacity: 1)
        case "stripe":  return Color(.sRGB, red: 0.55, green: 0.40, blue: 0.85, opacity: 1)
        case "slack":   return Color(.sRGB, red: 0.95, green: 0.40, blue: 0.65, opacity: 1)
        default:        return Color.white.opacity(0.4)
        }
    }

    private func relativeTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let s = -date.timeIntervalSinceNow
        if s < 60   { return "JUST NOW" }
        if s < 3600 { return "\(Int(s / 60))M AGO" }
        if s < 86400 { return "\(Int(s / 3600))H AGO" }
        return "\(Int(s / 86400))D AGO"
    }
}

private extension Color {
    static let cyanAccent   = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent  = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent    = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
    static let amberAccent  = Color(.sRGB, red: 0.99, green: 0.83, blue: 0.30, opacity: 1)
    static let purpleAccent = Color(.sRGB, red: 0.65, green: 0.45, blue: 0.95, opacity: 1)
}
