import SwiftUI
import Combine

// SyncStatusBadge
//
// Compact pill that shows whether the local cache sync is idle / running /
// errored, plus a relative "last synced N min ago" timestamp. Designed to
// drop into any toolbar, sidebar footer, or status bar — no surrounding
// chrome required.
//
// Tap to trigger a manual sync (kicks LumenSyncEngine.syncAll). Long-press
// or right-click reveals the full datasets surface via `onOpenConsole`.

struct SyncStatusBadge: View {
    @StateObject private var engine = LumenSyncEngine.shared
    var onOpenConsole: (() -> Void)? = nil

    @State private var hovering = false
    @State private var nowTick = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: triggerSync) {
            HStack(spacing: 6) {
                indicator
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering = $0 }
        .onReceive(tick) { date in nowTick = date }
        .contextMenu {
            Button("Sync now") { triggerSync() }
                .disabled(engine.isSyncing)
            if let onOpenConsole {
                Button("Open Lumen Console…", action: onOpenConsole)
            }
        }
    }

    // MARK: - Visual

    @ViewBuilder
    private var indicator: some View {
        if engine.isSyncing {
            ProgressView().controlSize(.small).tint(Color.cyanAccent)
        } else if engine.lastSyncError != nil {
            Circle().fill(Color.redAccent).frame(width: 6, height: 6)
        } else {
            Circle()
                .fill(Color.greenAccent)
                .frame(width: 6, height: 6)
                .shadow(color: Color.greenAccent.opacity(0.8), radius: 3)
        }
    }

    private var label: String {
        if engine.isSyncing { return "SYNCING" }
        if engine.lastSyncError != nil { return "SYNC ERROR" }
        guard let last = engine.lastFullSyncAt else { return "NOT YET SYNCED" }
        _ = nowTick  // consume so the view re-evaluates relativeTime on tick
        return "SYNCED \(relativeTime(last))"
    }

    private var textColor: Color {
        if engine.lastSyncError != nil { return Color.redAccent }
        if engine.isSyncing { return Color.cyanAccent }
        return engine.lastFullSyncAt == nil ? .white.opacity(0.45) : .white.opacity(0.7)
    }

    private var backgroundFill: Color {
        if engine.lastSyncError != nil { return Color.redAccent.opacity(0.1) }
        if engine.isSyncing { return Color.cyanAccent.opacity(0.1) }
        return hovering ? .white.opacity(0.05) : .white.opacity(0.025)
    }

    private var borderColor: Color {
        if engine.lastSyncError != nil { return Color.redAccent.opacity(0.5) }
        if engine.isSyncing { return Color.cyanAccent.opacity(0.45) }
        return .white.opacity(hovering ? 0.18 : 0.1)
    }

    private var helpText: String {
        if let err = engine.lastSyncError { return "Sync error: \(err)" }
        if engine.isSyncing { return "Pulling fresh rows from Supabase…" }
        if let last = engine.lastFullSyncAt {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .medium
            return "Last full sync: \(f.string(from: last)). Click to sync now."
        }
        return "Click to run the first cache sync."
    }

    // MARK: - Actions

    private func triggerSync() {
        Task { _ = await engine.syncAll() }
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
