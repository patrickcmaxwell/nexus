import SwiftUI
import Combine

// EndpointsView
//
// Health surface for the nexus-web HTTP API Lumen depends on. Renders a
// row per endpoint with its method, path, last-call status, and a Ping
// button that does a real round-trip and records the result.
//
// Why this exists: Patrick called out "Endpoints and datasets" as a
// placeholder area — datasets is covered by DatasetsView, this is the
// other half. When Lumen feels slow or stale, this view is the diagnostic
// surface to confirm whether nexus-web itself is the problem.

struct EndpointsView: View {
    @StateObject private var registry = EndpointHealthRegistry.shared
    @State private var pinging: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                bulkActions
                Divider().background(Color.white.opacity(0.06))
                grouped
            }
            .padding(24)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.cyanAccent)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.cyanAccent, radius: 4)
                Text("ENDPOINTS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color.cyanAccent.opacity(0.95))
            }
            Text("nexus-web API surface Lumen calls. Ping checks reachability + latency without authentication semantics.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var bulkActions: some View {
        HStack(spacing: 10) {
            Button(action: pingAll) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("PING ALL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(Color.cyanAccent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.cyanAccent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.cyanAccent.opacity(0.55), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!pinging.isEmpty)

            Text("HOST: \(hostLabel)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            if let healthy = healthSummary {
                Text(healthy.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(healthy.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(healthy.color.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(healthy.color.opacity(0.4), lineWidth: 1)
                    )
            }
        }
    }

    private var grouped: some View {
        let groups = Dictionary(grouping: EndpointCatalog.all) { $0.group }
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(EndpointCatalog.groups, id: \.self) { groupName in
                if let endpoints = groups[groupName], !endpoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(groupName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                        VStack(spacing: 1) {
                            ForEach(endpoints) { endpoint in
                                EndpointRow(
                                    endpoint: endpoint,
                                    health: registry.health[endpoint.id],
                                    isPinging: pinging.contains(endpoint.id),
                                    onPing: { ping(endpoint) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func ping(_ endpoint: EndpointDef) {
        pinging.insert(endpoint.id)
        Task {
            let result = await EndpointHealthRegistry.shared.ping(endpoint)
            await MainActor.run {
                pinging.remove(endpoint.id)
                _ = result
            }
        }
    }

    private func pingAll() {
        for endpoint in EndpointCatalog.all where endpoint.method == "GET" {
            ping(endpoint)
        }
    }

    private var hostLabel: String {
        let host = LumenAPIManager.shared.nexusBase
        if host.contains("localhost") { return "LOCAL DEV" }
        if let url = URL(string: host), let h = url.host { return h.uppercased() }
        return host
    }

    private var healthSummary: (label: String, color: Color)? {
        let known = registry.health.values
        guard !known.isEmpty else { return nil }
        let healthy = known.filter { $0.status == .ok }.count
        let total = known.count
        if healthy == total { return ("ALL \(total) HEALTHY", Color.greenAccent) }
        if healthy == 0     { return ("ALL \(total) DOWN",    Color.redAccent) }
        return ("\(healthy)/\(total) HEALTHY", Color(.sRGB, red: 0.95, green: 0.78, blue: 0.30, opacity: 1))
    }
}

// MARK: - Endpoint catalog

/// Static list of the nexus-web endpoints Lumen depends on. Lives here
/// (not on LumenAPIManager) because it's documentation as much as data —
/// adding a row here is how someone discovers what Lumen actually talks to.
struct EndpointDef: Identifiable, Equatable {
    let id: String         // unique key (also serves as path)
    let group: String      // visual grouping
    let method: String     // "GET" / "POST" / etc
    let path: String       // e.g. "/api/auth/me"
    let purpose: String    // one-line description
}

enum EndpointCatalog {
    static let groups = ["Auth", "Eve", "Operations", "Dashboard", "System"]

    static let all: [EndpointDef] = [
        // Auth
        EndpointDef(id: "/api/auth/me", group: "Auth", method: "GET", path: "/api/auth/me", purpose: "Current human profile + role"),
        EndpointDef(id: "/api/auth/known-users", group: "Auth", method: "GET", path: "/api/auth/known-users", purpose: "Team picker source"),
        EndpointDef(id: "/api/security/face/match", group: "Auth", method: "POST", path: "/api/security/face/match", purpose: "Native face capture → server descriptor match"),

        // Eve
        EndpointDef(id: "/api/eve",                group: "Eve", method: "POST", path: "/api/eve",               purpose: "Main chat (tools + memory + arena)"),
        EndpointDef(id: "/api/eve/local",          group: "Eve", method: "POST", path: "/api/eve/local",         purpose: "Local-LLM chat fallback"),
        EndpointDef(id: "/api/eve/conversations",  group: "Eve", method: "GET",  path: "/api/eve/conversations", purpose: "Conversation list with previews"),
        EndpointDef(id: "/api/eve/history",        group: "Eve", method: "GET",  path: "/api/eve/history",       purpose: "Per-conversation message log"),
        EndpointDef(id: "/api/eve/directives",     group: "Eve", method: "GET",  path: "/api/eve/directives",    purpose: "Operator-defined directives"),
        EndpointDef(id: "/api/eve/memory",         group: "Eve", method: "GET",  path: "/api/eve/memory",        purpose: "Eve memory bank"),
        EndpointDef(id: "/api/eve/briefing",       group: "Eve", method: "GET",  path: "/api/eve/briefing",      purpose: "What changed since last visit"),

        // Operations
        EndpointDef(id: "/api/operations",                       group: "Operations", method: "GET", path: "/api/operations",                       purpose: "Operations list + nested records/agents"),
        EndpointDef(id: "/api/operations/records",               group: "Operations", method: "GET", path: "/api/operations/records",               purpose: "Record CRUD"),
        EndpointDef(id: "/api/agents",                           group: "Operations", method: "GET", path: "/api/agents",                           purpose: "Agent registry"),
        EndpointDef(id: "/api/agents/run",                       group: "Operations", method: "POST", path: "/api/agents/run",                      purpose: "Manual agent run"),

        // Dashboard / Map
        EndpointDef(id: "/api/dashboard/overview", group: "Dashboard", method: "GET", path: "/api/dashboard/overview", purpose: "Dashboard counters + activity"),
        EndpointDef(id: "/api/nexus-map",          group: "Dashboard", method: "GET", path: "/api/nexus-map",          purpose: "Universe view nodes + edges"),
        EndpointDef(id: "/api/desktop/dashboard",  group: "Dashboard", method: "GET", path: "/api/desktop/dashboard",  purpose: "Desktop-only dashboard slim feed"),

        // System
        EndpointDef(id: "/api/llm/models",         group: "System", method: "GET", path: "/api/llm/models",         purpose: "Available LLM models"),
        EndpointDef(id: "/api/mentions/search",    group: "System", method: "GET", path: "/api/mentions/search",    purpose: "@-mention picker"),
        EndpointDef(id: "/api/arena/log",          group: "System", method: "GET", path: "/api/arena/log",          purpose: "Arena executor audit log"),
    ]
}

// MARK: - Health registry

@MainActor
final class EndpointHealthRegistry: ObservableObject {
    static let shared = EndpointHealthRegistry()

    @Published var health: [String: HealthResult] = [:]

    struct HealthResult: Equatable {
        let status: Status
        let httpCode: Int?
        let latencyMs: Int
        let checkedAt: Date
        let detail: String?

        enum Status: String {
            case ok
            case warn   // 4xx — alive but auth/perm issue, still "reachable"
            case down   // 5xx, timeout, network error
            case unknown
        }
    }

    /// Issue an unauthenticated GET to the endpoint and record the result.
    /// We treat any HTTP response (including 401) as "reachable" — auth
    /// errors don't mean the server is down.
    func ping(_ endpoint: EndpointDef) async -> HealthResult {
        guard endpoint.method == "GET" else {
            // POST endpoints we don't probe (we'd need to know what to send).
            // Mark them unknown so they don't show as failed.
            let result = HealthResult(status: .unknown, httpCode: nil, latencyMs: 0,
                                      checkedAt: Date(), detail: "Probe not implemented for \(endpoint.method)")
            health[endpoint.id] = result
            return result
        }
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)\(endpoint.path)") else {
            let result = HealthResult(status: .down, httpCode: nil, latencyMs: 0,
                                      checkedAt: Date(), detail: "Bad URL")
            health[endpoint.id] = result
            return result
        }

        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "GET"
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
        }

        let started = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let status: HealthResult.Status
            switch code {
            case 200..<300: status = .ok
            case 400..<500: status = .warn
            default:        status = .down
            }
            let result = HealthResult(status: status, httpCode: code, latencyMs: latency,
                                      checkedAt: Date(), detail: nil)
            health[endpoint.id] = result
            return result
        } catch {
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            let result = HealthResult(status: .down, httpCode: nil, latencyMs: latency,
                                      checkedAt: Date(), detail: (error as NSError).localizedDescription)
            health[endpoint.id] = result
            return result
        }
    }
}

// MARK: - Row

private struct EndpointRow: View {
    let endpoint: EndpointDef
    let health: EndpointHealthRegistry.HealthResult?
    let isPinging: Bool
    let onPing: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            methodBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.path)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Text(endpoint.purpose)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            statusBlock
            Button(action: onPing) {
                if isPinging {
                    ProgressView().controlSize(.small).tint(Color.cyanAccent)
                } else {
                    Text("PING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color.cyanAccent)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 50, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.cyanAccent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.cyanAccent.opacity(0.4), lineWidth: 1)
            )
            .disabled(isPinging)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.025))
    }

    private var methodBadge: some View {
        Text(endpoint.method)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(methodColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(methodColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(methodColor.opacity(0.4), lineWidth: 1)
            )
            .frame(width: 48)
    }

    private var methodColor: Color {
        switch endpoint.method {
        case "GET":    return Color(.sRGB, red: 0.45, green: 0.85, blue: 0.65, opacity: 1)
        case "POST":   return Color(.sRGB, red: 0.95, green: 0.78, blue: 0.30, opacity: 1)
        case "PATCH":  return Color(.sRGB, red: 0.65, green: 0.55, blue: 0.95, opacity: 1)
        case "DELETE": return Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
        default:       return .white.opacity(0.4)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if let h = health {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(for: h.status))
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor(for: h.status).opacity(0.6), radius: 3)
                if let code = h.httpCode {
                    Text("\(code)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor(for: h.status))
                } else {
                    Text("—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Text(h.latencyMs > 0 ? "\(h.latencyMs)MS" : "")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(minWidth: 50, alignment: .trailing)
            }
        } else {
            Text("UNTESTED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.3))
                .frame(minWidth: 80, alignment: .trailing)
        }
    }

    private func statusColor(for s: EndpointHealthRegistry.HealthResult.Status) -> Color {
        switch s {
        case .ok:      return Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
        case .warn:    return Color(.sRGB, red: 0.95, green: 0.78, blue: 0.30, opacity: 1)
        case .down:    return Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
        case .unknown: return .white.opacity(0.4)
        }
    }
}

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
