import SwiftUI
import AppKit
import SwiftTerm

/// Tabbed Claude Code session browser.
///
/// Architecture:
///   - All session lifetime lives in `LumenAppRegistry` (an EnvironmentObject
///     installed at the App root). Sessions persist across navigation and
///     across panel tear-down/rebuild.
///   - This view borrows references to render: a tab strip across the top,
///     the active session's terminal embedded below via re-parenting host.
///   - When the Director navigates away, this view tears down — sessions
///     stay alive in the registry. Navigating back rebuilds the view and
///     reattaches the existing terminal NSViews to the new container.
///
/// What you can do here:
///   - Launch a new session in any folder (folder picker or recent list)
///   - Run multiple sessions simultaneously — each its own tab
///   - Click a tab to focus its terminal
///   - Click the X on a tab to terminate that session
///   - Sidebar Code row shows running-session count badge
struct CodePanel: View {
    @ObservedObject var store: LumenStore
    @EnvironmentObject var registry: LumenAppRegistry
    let onClose: () -> Void

    @AppStorage("lumen.code.recentFolders") private var recentFoldersRaw: String = ""
    @AppStorage("lumen.code.claudePath")    private var claudePath: String = ""
    @State private var activeSessionId: UUID? = nil
    @State private var hint: String = ""

    private var recentFolders: [String] {
        recentFoldersRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private var activeSession: CodeSession? {
        registry.codeSessions.first { $0.id == activeSessionId }
            ?? registry.codeSessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if registry.codeSessions.isEmpty {
                launcher
            } else {
                tabStrip
                Divider()
                if let session = activeSession {
                    SessionContainer(session: session)
                        .id(session.id)
                } else {
                    Color.clear
                }
            }
        }
        .background(C.bg)
        .onAppear {
            if claudePath.isEmpty { claudePath = autoDetectClaudePath() }
            if activeSessionId == nil {
                activeSessionId = registry.codeSessions.first?.id
            }
        }
        .onChange(of: registry.codeSessions.count) { _, _ in
            // If the active session was just terminated, slide focus to
            // another running session (or back to the launcher).
            if !registry.codeSessions.contains(where: { $0.id == activeSessionId }) {
                activeSessionId = registry.codeSessions.first?.id
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 13)).foregroundColor(C.eve)
            Text("CODE · CLAUDE CODE INSIDE LUMEN")
                .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.4)
                .foregroundColor(.primary.opacity(0.85))
            if registry.runningCodeCount > 0 {
                runningPill
            }
            Spacer()
            if !registry.codeSessions.isEmpty {
                Button(action: { pickFolder() }) {
                    Label("New Session", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(C.eve)
                .help("Launch Claude Code in another folder (each session runs independently)")
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var runningPill: some View {
        HStack(spacing: 5) {
            Circle().fill(C.listen).frame(width: 6, height: 6)
                .shadow(color: C.listen, radius: 3)
            Text("\(registry.runningCodeCount) RUNNING")
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4)
                .foregroundColor(C.listen)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(C.listen.opacity(0.10), in: Capsule())
    }

    // MARK: Tab strip

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(registry.codeSessions) { session in
                    SessionTab(
                        session: session,
                        isActive: session.id == activeSessionId,
                        onSelect: { activeSessionId = session.id },
                        onClose:  { registry.remove(session) }
                    )
                }
                Button(action: { pickFolder() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 24)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("New Claude Code session")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(C.surfaceHi.opacity(0.5))
    }

    // MARK: Launcher (no sessions)

    private var launcher: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroIntro
                claudePathRow
                pickFolderCTA
                if !recentFolders.isEmpty { recentList }
                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11)).foregroundColor(C.danger)
                        .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var heroIntro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run Claude Code inside Lumen")
                .font(.system(size: 19, weight: .semibold))
            Text("Pick a folder. Each session runs independently and persists across navigation — start one, switch to Eve, and it keeps working.")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private var claudePathRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 11)).foregroundColor(C.think)
            TextField("Path to claude binary", text: $claudePath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            Button("Auto-detect") { claudePath = autoDetectClaudePath() }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var pickFolderCTA: some View {
        Button(action: pickFolder) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(C.eve.opacity(0.22)).frame(width: 38, height: 38)
                    Image(systemName: "folder.fill.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(C.eve)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a working directory…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.95))
                    Text("Lumen will run Claude Code rooted at this folder")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18)).foregroundColor(C.eve.opacity(0.85))
            }
            .padding(14)
            .background(LinearGradient(colors: [C.eve.opacity(0.12), C.eve.opacity(0.04)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(C.eve.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT FOLDERS")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.8)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recentFolders, id: \.self) { path in
                    Button(action: { launch(folder: path) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11)).foregroundColor(C.eve.opacity(0.7))
                            Text(prettyPath(path))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.9))
                                .lineLimit(1).truncationMode(.head)
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 9)).foregroundColor(C.listen)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(C.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func prettyPath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    // MARK: Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.message                 = "Choose the folder Claude Code should work in"
        panel.prompt                  = "Launch"
        if panel.runModal() == .OK, let url = panel.url {
            launch(folder: url.path)
        }
    }

    private func launch(folder: String) {
        var fs = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &fs), fs.boolValue else {
            hint = "Folder no longer exists: \(folder)"
            return
        }
        let path = resolveClaudePath()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            hint = "Claude binary not executable at \(path). Set the path above."
            return
        }
        hint = ""
        rememberRecent(folder)
        let session = registry.startCodeSession(folder: folder, claudePath: path)
        activeSessionId = session.id
    }

    private func rememberRecent(_ folder: String) {
        var list = recentFolders.filter { $0 != folder }
        list.insert(folder, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        recentFoldersRaw = list.joined(separator: "\n")
    }

    private func resolveClaudePath() -> String {
        if !claudePath.isEmpty { return claudePath }
        return autoDetectClaudePath()
    }

    /// Probes the common install locations for the Claude Code CLI. Falls
    /// back to the literal string "claude" so PATH lookups can resolve when
    /// the launching shell happens to know where it lives.
    private func autoDetectClaudePath() -> String {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/.volta/bin/claude",
            "\(NSHomeDirectory())/.bun/bin/claude",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }

        // Walk every Node version under nvm — the Director runs nvm.
        let nvmRoot = "\(NSHomeDirectory())/.nvm/versions/node"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            for entry in entries {
                let candidate = "\(nvmRoot)/\(entry)/bin/claude"
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return "claude"
    }
}

// MARK: - Tab

private struct SessionTab: View {
    @ObservedObject var session: CodeSession
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.status.isRunning ? C.listen : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
                .shadow(color: session.status.isRunning ? C.listen : .clear, radius: 3)
            Button(action: onSelect) {
                Text(session.title)
                    .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("End this session")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isActive ? C.eve.opacity(0.16) : C.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
            isActive ? C.eve.opacity(0.4) : C.hairline, lineWidth: 1))
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Session container (re-parenting host)

/// Wraps the `SessionTerminalHost` with footer status text. Receives the
/// CodeSession as @ObservedObject so status changes (running → exited)
/// re-render the footer without rebuilding the embedded NSView.
private struct SessionContainer: View {
    @ObservedObject var session: CodeSession

    var body: some View {
        VStack(spacing: 0) {
            SessionTerminalHost(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            sessionFooter
        }
    }

    private var sessionFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9)).foregroundColor(C.eve.opacity(0.7))
            Text(session.folder)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.head)
            Spacer()
            Text(session.status.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(session.status.isRunning ? C.listen : C.danger.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
