import SwiftUI
import AppKit

// DatasetsView
//
// Surface for the local SQLite cache: which tables are mirrored, how many
// rows we have, when each was last synced, file size on disk, and the
// "Sync now" + "Reset cache" controls. Lives standalone so it can be
// dropped into any panel — slot it into the System panel, hand it its own
// dock-able window, or render it in Settings.
//
// Goes hand-in-hand with LumenLocalDB + LumenSyncEngine: this is the
// human-facing readout for what those layers are doing in the background.

struct DatasetsView: View {
    @EnvironmentObject var sync: LumenSync
    @StateObject private var engine = LumenSyncEngine.shared

    @State private var rows: [TableSnapshot] = []
    @State private var fileSize: Int64 = -1
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var lastError: String? = nil

    /// One row per cached table — populates the readout list.
    struct TableSnapshot: Identifiable, Equatable {
        let table: String
        let rowCount: Int
        let lastSyncedAt: Date?
        var id: String { table }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                syncControls
                Divider().background(Color.white.opacity(0.06))
                tablesSection
                Divider().background(Color.white.opacity(0.06))
                storageSection
            }
            .padding(24)
        }
        .background(Color.black.opacity(0.001))  // capture clicks for the scroll view
        .onAppear { reload() }
        .onReceive(engine.$isSyncing) { active in
            // After a sync wraps, refresh the readout so the row counts
            // reflect what just landed.
            if !active { reload() }
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
                Text("DATASETS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color.cyanAccent.opacity(0.95))
            }
            Text("Local cache mirrors of nexus-web tables. Reads paint instantly; sync fills in the background.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var syncControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: triggerSync) {
                    HStack(spacing: 6) {
                        if engine.isSyncing {
                            ProgressView().controlSize(.small).tint(Color.cyanAccent)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        }
                        Text(engine.isSyncing ? "SYNCING…" : "SYNC NOW")
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
                .disabled(engine.isSyncing)

                if let last = engine.lastFullSyncAt {
                    Text("LAST FULL SYNC \(relativeTime(last))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("NEVER SYNCED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
            }

            if let err = engine.lastSyncError ?? lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.redAccent)
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(Color.redAccent.opacity(0.9))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.redAccent.opacity(0.08))
                )
            }
        }
    }

    private var tablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CACHED TABLES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("ROWS · LAST SYNC")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.3))
            }
            VStack(spacing: 1) {
                ForEach(rows) { row in
                    DatasetRow(snapshot: row)
                }
                if rows.isEmpty {
                    Text(engine.isSyncing ? "Loading…" : "No tables cached yet — Sync now to populate")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ON-DISK CACHE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white.opacity(0.4))

            if let url = LumenLocalDB.fileURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .textSelection(.enabled)
                    HStack(spacing: 14) {
                        Text(fileSizeLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Button("REVEAL IN FINDER") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color.cyanAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.cyanAccent.opacity(0.4), lineWidth: 1)
                        )
                        Button("RESET CACHE") {
                            confirmReset()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color.redAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.redAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                }
            }

            Text("Cache is single-user (Patrick only). When Lumen goes multi-user this view will scope per active human.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 4)
        }
    }

    // MARK: - Actions

    private func triggerSync() {
        Task {
            lastError = nil
            _ = await engine.syncAll()
            reload()
        }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset local cache?"
        alert.informativeText = "Every cached row gets dropped. Watermarks reset, so the next Sync now pulls everything fresh. The remote database is untouched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        Task {
            await LumenLocalDB.shared.resetCache()
            reload()
        }
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task {
            let counts = await LumenLocalDB.shared.tableRowCounts()
            let states = await LumenLocalDB.shared.allSyncStates()
            let stateByTable = Dictionary(uniqueKeysWithValues: states.map { ($0.table, $0.lastSyncedAt) })
            let snapshots = counts.map { c in
                TableSnapshot(table: c.table, rowCount: c.rows, lastSyncedAt: stateByTable[c.table] ?? nil)
            }
            await MainActor.run {
                self.rows = snapshots
                self.fileSize = LumenLocalDB.fileSizeBytes
            }
        }
    }

    private var fileSizeLabel: String {
        guard fileSize >= 0 else { return "—" }
        let kb = Double(fileSize) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB", mb)
    }

    private func relativeTime(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60   { return "JUST NOW" }
        if s < 3600 { return "\(Int(s / 60))M AGO" }
        if s < 86400 { return "\(Int(s / 3600))H AGO" }
        return "\(Int(s / 86400))D AGO"
    }
}

// MARK: - Row

private struct DatasetRow: View {
    let snapshot: DatasetsView.TableSnapshot

    var body: some View {
        HStack(spacing: 12) {
            // Friendly name + row count
            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: snapshot.table))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(snapshot.table)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            Text("\(snapshot.rowCount)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(snapshot.rowCount > 0 ? Color.greenAccent : .white.opacity(0.35))
                .frame(minWidth: 50, alignment: .trailing)
            Text(syncedLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.45))
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
    }

    private func label(for table: String) -> String {
        switch table {
        case "conversations":     return "Conversations"
        case "messages":          return "Messages"
        case "operations":        return "Operations"
        case "operation_records": return "Records"
        case "agents":            return "Agents"
        case "directives":        return "Directives"
        case "memories":          return "Memory bank"
        default:                  return table.capitalized
        }
    }

    private var syncedLabel: String {
        guard let synced = snapshot.lastSyncedAt else { return "NEVER" }
        let s = -synced.timeIntervalSinceNow
        if s < 60   { return "JUST NOW" }
        if s < 3600 { return "\(Int(s / 60))M AGO" }
        if s < 86400 { return "\(Int(s / 3600))H AGO" }
        return "\(Int(s / 86400))D AGO"
    }
}

// MARK: - Color shorthand (mirrors NativeFaceCaptureView / AuthWebView)

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
