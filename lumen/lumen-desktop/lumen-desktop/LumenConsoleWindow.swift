import SwiftUI

// LumenConsoleWindow
//
// A standalone window that surfaces all the local-cache machinery: the
// datasets readout (per-table row counts + sync state) and a launchpad for
// the unified search. Reachable from the Panels menu (Cmd-Opt-D) so users
// can monitor + control sync without us touching MainView.
//
// As MainView gets cache-front for more panels, this stays useful as the
// "engine room" view — somewhere to verify what's actually cached + force
// a refresh after a network blip.

struct LumenConsoleWindow: View {
    @EnvironmentObject var sync: LumenSync
    @StateObject private var arenaHealth = LumenArenaHealth.shared
    @State private var tab: ConsoleTab = .today
    @State private var showSearch: Bool = false
    @State private var lastSearchHit: LumenLocalDB.SearchHit? = nil

    enum ConsoleTab: String, CaseIterable, Identifiable {
        case today     = "Today"
        case arena     = "Arena"
        case datasets  = "Datasets"
        case endpoints = "Endpoints"
        case search    = "Search"
        case status    = "Status"
        case settings  = "Settings"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.06))
                tabContent
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .preferredColorScheme(.dark)
        .overlay(
            SearchPalette(isPresented: $showSearch) { hit in
                lastSearchHit = hit
            }
        )
    }

    // MARK: - Sections

    private var background: some View {
        ZStack {
            Color(.sRGB, red: 0.04, green: 0.05, blue: 0.07, opacity: 1).ignoresSafeArea()
            Canvas { ctx, size in
                let spacing: CGFloat = 56
                ctx.opacity = 0.04
                var x: CGFloat = 0
                while x <= size.width {
                    ctx.stroke(Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }, with: .color(.white), lineWidth: 0.5)
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    ctx.stroke(Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }, with: .color(.white), lineWidth: 0.5)
                    y += spacing
                }
            }.ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.cyanAccent)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.cyanAccent, radius: 4)
                Text("LUMEN CONSOLE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.85))
            }
            tabPicker
            Spacer()
            SyncStatusBadge()
                .environmentObject(sync)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(ConsoleTab.allCases) { t in
                Button(action: { tab = t }) {
                    HStack(spacing: 5) {
                        Text(t.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                        // Arena tab gets a red dot when any connection is errored
                        if t == .arena && arenaHealth.erroredCount > 0 {
                            Circle()
                                .fill(Color.redAccent)
                                .frame(width: 5, height: 5)
                                .shadow(color: Color.redAccent.opacity(0.8), radius: 3)
                        }
                    }
                    .foregroundColor(tab == t ? Color.cyanAccent : .white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tab == t ? Color.cyanAccent.opacity(0.12) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tab == t ? Color.cyanAccent.opacity(0.4) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(t == .arena && arenaHealth.erroredCount > 0
                    ? "\(arenaHealth.erroredCount) Arena connection\(arenaHealth.erroredCount == 1 ? "" : "s") need attention"
                    : "")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { LumenArenaHealth.shared.startPolling() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .today:
            LumenBriefingView()
        case .arena:
            LumenArenaView()
        case .datasets:
            DatasetsView()
                .environmentObject(sync)
        case .endpoints:
            EndpointsView()
        case .search:
            searchLauncher
        case .status:
            statusReadout
        case .settings:
            LumenSettingsView()
        }
    }

    private var searchLauncher: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("UNIFIED SEARCH")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(Color.cyanAccent.opacity(0.95))
            Text("Searches the local cache across conversations, operations, records, agents, memories, and directives. Instant — no network round-trip per keystroke.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
            Button(action: { showSearch = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    Text("OPEN SEARCH PALETTE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(Color.cyanAccent)
                .padding(.horizontal, 14).padding(.vertical, 10)
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

            if let hit = lastSearchHit {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST OPENED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.4))
                    HStack(spacing: 8) {
                        Text(hit.kind.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(Color.cyanAccent.opacity(0.9))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.cyanAccent.opacity(0.4), lineWidth: 1)
                            )
                        Text(hit.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    if !hit.snippet.isEmpty {
                        Text(hit.snippet)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusReadout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("SYNC STATUS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color.cyanAccent.opacity(0.95))

                statusRow("Dashboard refresh",  date: sync.lastDashboardSync,        cadence: "20s")
                statusRow("Conversation list",  date: sync.lastConversationsSync,    cadence: "45s")
                statusRow("Directives + memory", date: sync.lastDirectivesMemorySync, cadence: "90s")
                statusRow("Nexus map",          date: sync.lastMapSync,              cadence: "120s (only when open)")
                statusRow("Local DB delta sync", date: sync.lastLocalDBSync,         cadence: "300s + manual")

                Spacer()
            }
            .padding(24)
        }
    }

    private func statusRow(_ label: String, date: Date?, cadence: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("Cadence: \(cadence)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            if let date {
                Text(relativeTime(date))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Text("PENDING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
    }

    private func relativeTime(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60   { return "JUST NOW" }
        if s < 3600 { return "\(Int(s / 60))M AGO" }
        if s < 86400 { return "\(Int(s / 3600))H AGO" }
        return "\(Int(s / 86400))D AGO"
    }
}

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
