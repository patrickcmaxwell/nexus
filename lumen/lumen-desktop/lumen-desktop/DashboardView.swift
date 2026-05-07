import SwiftUI

/// Lumen's new default landing surface. Replaces the cold "open straight
/// into Live chat" experience with a state-of-affairs mission report so the
/// Director can orient before engaging.
///
/// Layout (top → bottom):
/// 1. Hero greeting (time-of-day + Eve avatar)
/// 2. Mission Report card (delta from /api/eve/briefing)
/// 3. Recent Conversations rail (click any → loads into Live)
/// 4. Big "Start Fresh Session" CTA
/// 5. System status strip (brain, voice, ops)
///
/// All taps that engage a conversation flip `store.viewMode` to `.live`,
/// where the existing thread + composer take over. The Director can return
/// here with the "Back to Dashboard" button in the Live header.
struct DashboardView: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool

    @State private var didInitialFetch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroHeader
                briefingCard
                recentRail
                startFreshCTA
                systemStrip
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(C.bg)
        .task {
            // Refresh the briefing once per dashboard open; user can pull
            // again via the refresh affordance on the briefing card.
            if !didInitialFetch {
                didInitialFetch = true
                await store.fetchBriefingDelta()
                if store.conversations.isEmpty { await store.fetchDashboard() }
            }
        }
    }

    // MARK: Hero

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning, Director."
        case 12..<17: return "Good afternoon, Director."
        case 17..<22: return "Good evening, Director."
        default:      return "Late night, Director."
        }
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            // Pulse ring around an Eve sigil
            ZStack {
                Circle().stroke(C.eve.opacity(0.35), lineWidth: 1)
                    .frame(width: 56, height: 56)
                Circle().fill(C.eve.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(C.eve)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.95))
                Text("MISSION REPORT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(C.eve.opacity(0.85))
            }
            Spacer()
        }
    }

    // MARK: Briefing card

    @ViewBuilder
    private var briefingCard: some View {
        let delta = store.briefingDelta
        DashboardCard(title: "STATE OF AFFAIRS", accent: C.eve, trailing: {
            AnyView(
                Button(action: { Task { await store.fetchBriefingDelta() } }) {
                    Image(systemName: store.briefingLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh briefing"))
        }) {
            if store.briefingLoading && delta == nil {
                HStack { ProgressView().controlSize(.small); Text("Compiling briefing…").foregroundColor(.secondary) }
                    .padding(.vertical, 6)
            } else if let d = delta {
                briefingBody(d)
            } else {
                Text("No briefing yet — pull when ready.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func briefingBody(_ d: BriefingDelta) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top stats row
            HStack(spacing: 8) {
                statChip(icon: "flag.fill", count: d.activeOps,        label: "OPS",        color: C.eve)
                statChip(icon: "person.2.fill", count: d.activeAgents, label: "AGENTS",     color: C.listen)
                statChip(icon: "scroll.fill", count: d.activeDirectives, label: "DIRECTIVES", color: C.think)
                statChip(icon: "brain.head.profile", count: d.memories, label: "MEMORIES",  color: .secondary)
                Spacer()
            }

            if d.hasAnyDelta {
                // Delta lines — each represents motion since last visit
                if !d.newOperations.isEmpty {
                    deltaLine(icon: "plus.circle.fill", color: C.listen,
                              text: "\(d.newOperations.count) new operation\(d.newOperations.count == 1 ? "" : "s"): \(d.newOperations.prefix(2).map { $0.label }.joined(separator: ", "))")
                }
                if !d.statusChangedOperations.isEmpty {
                    deltaLine(icon: "arrow.triangle.2.circlepath", color: C.think,
                              text: "\(d.statusChangedOperations.count) op\(d.statusChangedOperations.count == 1 ? "" : "s") moved status")
                }
                if !d.newRecords.isEmpty {
                    deltaLine(icon: "doc.fill", color: C.eve,
                              text: "\(d.newRecords.count) new record\(d.newRecords.count == 1 ? "" : "s")")
                }
                if d.findingTotal > 0 {
                    deltaLine(icon: "magnifyingglass", color: C.listen,
                              text: "\(d.findingTotal) research finding\(d.findingTotal == 1 ? "" : "s") logged")
                }
                if !d.completedResearch.isEmpty {
                    deltaLine(icon: "checkmark.seal.fill", color: C.listen,
                              text: "\(d.completedResearch.count) research thread\(d.completedResearch.count == 1 ? "" : "s") completed")
                }
            } else {
                Text("Nothing new since last visit.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func statChip(icon: String, count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundColor(color)
            Text("\(count)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.primary.opacity(0.92))
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.06), in: Capsule())
    }

    private func deltaLine(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundColor(.primary.opacity(0.85))
            Spacer()
        }
    }

    // MARK: Recent conversations rail

    private var recentRail: some View {
        DashboardCard(title: "RECENT CONVERSATIONS", accent: C.listen, trailing: { AnyView(EmptyView()) }) {
            let recent = store.conversations.prefix(6)
            if recent.isEmpty {
                Text("No conversations yet — kick one off below.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(Array(recent), id: \.id) { conv in
                        Button(action: { store.engageLive(conversationId: conv.id, title: conv.title) }) {
                            convCard(conv)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func convCard(_ conv: ConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 10)).foregroundColor(C.eve.opacity(0.85))
                Text(conv.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                Spacer()
                Text(relativeTime(conv.updatedAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if !conv.preview.isEmpty {
                Text(conv.preview)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                Text(conv.source.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4)
                    .foregroundColor(.secondary.opacity(0.7))
                if conv.messageCount > 0 {
                    Text("· \(conv.messageCount) MSG\(conv.messageCount == 1 ? "" : "S")")
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Fresh session CTA

    private var startFreshCTA: some View {
        Button(action: { store.engageLive() }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(C.eve.opacity(0.22)).frame(width: 38, height: 38)
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(C.eve)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a Fresh Session")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.95))
                    Text("Open a new live conversation with Eve")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(C.eve.opacity(0.85))
            }
            .padding(14)
            .background(C.eve.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command])
        .help("⌘N — opens Live with a fresh thread")
    }

    // MARK: System status strip

    private var systemStrip: some View {
        HStack(spacing: 14) {
            statusPill(label: "BRAIN", value: brainLabel, color: brainColor)
            statusPill(label: "VOICE", value: voiceLabel, color: voiceColor)
            statusPill(label: "EVE",   value: store.eveStatus.label.uppercased(), color: store.eveStatus.color)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var brainLabel: String {
        switch lmStatus {
        case .checking: return "CHECKING"
        case .offline:  return "GROK ONLY"
        case .online(let m): return m.isEmpty ? "LOCAL READY" : m.prefix(14).uppercased()
        }
    }

    private var brainColor: Color {
        switch lmStatus {
        case .checking: return .secondary
        case .offline:  return C.think
        case .online:   return C.listen
        }
    }

    private var voiceLabel: String {
        if store.voiceClaimedBy != nil { return "ACTIVE" }
        return "READY"
    }

    private var voiceColor: Color {
        store.voiceClaimedBy != nil ? C.listen : .secondary
    }

    private func statusPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3)
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2)
                .foregroundColor(.primary.opacity(0.85))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Reusable card chrome

private struct DashboardCard<Content: View>: View {
    let title: String
    let accent: Color
    let trailing: () -> AnyView
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(accent.opacity(0.6)).frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(1.8)
                    .foregroundColor(.primary.opacity(0.7))
                Spacer()
                trailing()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
