// LumenTerminalBridge.swift
//
// Publishes the Mac's Claude Code sessions to nexus-web so the iOS Nexus
// app can see them, watch their output, and send input. Without this
// bridge, every CodeSession is a black box to the phone — SwiftTerm
// PTYs live on the Mac and nothing else can reach them.
//
// What this file does:
//   1. Observes `LumenAppRegistry.codeSessions`. When a new session
//      shows up, POSTs to /api/terminal/sessions and remembers the
//      server-assigned id locally.
//   2. Every `heartbeatInterval` (30s) while a session is running,
//      snapshots its visible buffer text (via SwiftTerm's
//      `getBufferAsData`) and PATCHes the row.
//   3. Every `commandPollInterval` (5s), GETs pending commands for each
//      running session and `.send`s them into the PTY, then PATCHes
//      each command to status='dispatched'.
//   4. On session exit (status flips off `.running`), PATCHes the row
//      with the new status + exit_code.
//
// Why polling rather than SSE / Supabase Realtime: this v1 ships
// end-to-end without changing the iOS network layer. Once the loop is
// proven, we can upgrade to push-style streaming behind the same
// interface.
//
// Failure handling: every network call is best-effort. A flaky network
// must not break the actual local terminal experience — sessions keep
// running locally even if the server side is unreachable for hours.
// The next heartbeat will catch up.

import Foundation
import Combine
import SwiftTerm
import AppKit

@MainActor
final class LumenTerminalBridge {
    static let shared = LumenTerminalBridge()

    /// How often to push a buffer snapshot + heartbeat for each running
    /// session. Matches the 2-minute staleness window the server uses to
    /// mark a session as `stale` — three missed heartbeats and the phone
    /// will warn.
    private let heartbeatInterval: TimeInterval = 30

    /// How often to ask the server "any commands queued for my sessions?"
    /// Low enough to feel responsive when the user taps a command on the
    /// phone, high enough to not hammer Vercel.
    private let commandPollInterval: TimeInterval = 5

    /// Server-side terminal_sessions.id for each local CodeSession.
    /// Filled in after the POST /api/terminal/sessions response.
    private var serverIds: [UUID: String] = [:]

    /// Cache of CodeSession.status we already PATCHed so we don't spam
    /// the server with the same exited-status PATCH on every heartbeat
    /// tick once a session has stopped running.
    private var lastPublishedStatus: [UUID: String] = [:]

    private var heartbeatTimer: Timer?
    private var commandTimer: Timer?
    private var registryCancellable: AnyCancellable?
    private weak var registry: LumenAppRegistry?

    private init() {}

    /// Wire up the bridge to the live app registry. Called once at app
    /// launch (from AppDelegate / @main App init) after auth has been
    /// restored — LumenAPIManager.sessionCookie must be set or all POSTs
    /// will fail and we'll just keep retrying until the user signs in.
    func start(registry: LumenAppRegistry) {
        self.registry = registry

        // Observe the live session list. Each emission gives us the full
        // current set — we reconcile by registering any new IDs we
        // haven't seen and de-registering any IDs that disappeared.
        registryCancellable = registry.$codeSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                Task { @MainActor in self?.reconcile(sessions) }
            }

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeatAll() }
        }
        commandTimer = Timer.scheduledTimer(withTimeInterval: commandPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollCommandsAll() }
        }
    }

    func stop() {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        commandTimer?.invalidate(); commandTimer = nil
        registryCancellable?.cancel(); registryCancellable = nil
    }

    // MARK: - Reconciliation

    private func reconcile(_ sessions: [CodeSession]) {
        let currentIds = Set(sessions.map(\.id))

        // Register any new sessions
        for s in sessions where serverIds[s.id] == nil {
            Task { await register(s) }
        }

        // Drop server ID mappings for sessions the registry no longer holds.
        // We don't try to PATCH the server for those — the heartbeat-staleness
        // window will mark them as stale on its own. Could also fire-and-
        // forget a status='exited' PATCH here; preferring the simpler path.
        for id in serverIds.keys where !currentIds.contains(id) {
            serverIds.removeValue(forKey: id)
            lastPublishedStatus.removeValue(forKey: id)
        }
    }

    // MARK: - Server I/O

    private func register(_ session: CodeSession) async {
        let payload: [String: Any] = [
            "mac_label":   Self.macLabel(),
            "folder":      session.folder,
            "claude_path": session.claudePath,
            "title":       session.title,
        ]
        guard let resp: [String: Any] = await postJSON(path: "/api/terminal/sessions", body: payload, statusOK: 201) else {
            // Try again next reconcile cycle (next time @Published fires)
            return
        }
        if let id = resp["id"] as? String {
            serverIds[session.id] = id
            lastPublishedStatus[session.id] = "running"
        }
    }

    private func heartbeatAll() {
        guard let registry = registry else { return }
        for session in registry.codeSessions {
            guard let serverId = serverIds[session.id] else { continue }
            Task { await heartbeat(session: session, serverId: serverId) }
        }
    }

    private func heartbeat(session: CodeSession, serverId: String) async {
        let snapshot = snapshotText(session: session)
        let statusLabel = statusString(session.status)

        var body: [String: Any] = [
            "last_snapshot": snapshot,
            "title":         session.title,
        ]
        // Status transitions: only PATCH a non-running status once. We
        // still PATCH a 'running' status every heartbeat — that doubles
        // as the heartbeat ping on the server (last_heartbeat_at is
        // touched on every PATCH).
        if statusLabel != "running" && lastPublishedStatus[session.id] != statusLabel {
            body["status"] = statusLabel
            if case .exited(let code) = session.status, let code {
                body["exit_code"] = Int(code)
            }
            lastPublishedStatus[session.id] = statusLabel
        }
        _ = await patchJSON(path: "/api/terminal/sessions/\(serverId)", body: body)
    }

    private func pollCommandsAll() {
        guard let registry = registry else { return }
        for session in registry.codeSessions where session.status.isRunning {
            guard let serverId = serverIds[session.id] else { continue }
            Task { await pollCommands(session: session, serverId: serverId) }
        }
    }

    private func pollCommands(session: CodeSession, serverId: String) async {
        guard let resp: [String: Any] = await getJSON(path: "/api/terminal/commands?session_id=\(serverId)") else {
            return
        }
        guard let commands = resp["commands"] as? [[String: Any]] else { return }
        for cmd in commands {
            guard let cmdId  = cmd["id"]      as? String,
                  let cmdStr = cmd["command"] as? String else { continue }

            // Feed bytes into the PTY. SwiftTerm's `.send(txt:)` writes
            // directly to the child process's stdin. Caller is expected
            // to include a trailing \n when they want a command to be
            // executed by the shell / Claude prompt — we don't add one
            // for them so they can also send control sequences (Ctrl-C,
            // tab completion, etc) without us mangling them.
            session.terminalView.send(txt: cmdStr)

            _ = await patchJSON(
                path: "/api/terminal/commands/\(cmdId)",
                body: ["status": "dispatched"]
            )
        }
    }

    // MARK: - Helpers

    /// Read the visible buffer of a session as UTF-8 text. Truncated to
    /// avoid pushing megabytes over a heartbeat — the phone viewer
    /// shows the tail anyway.
    private func snapshotText(session: CodeSession) -> String {
        let term = session.terminalView.getTerminal()
        let data = term.getBufferAsData(kind: .active, encoding: .utf8)
        let text = String(data: data, encoding: .utf8) ?? ""
        let maxBytes = 32_000
        if text.utf8.count <= maxBytes { return text }
        let suffix = String(text.suffix(maxBytes))
        return "[…truncated…]\n" + suffix
    }

    private func statusString(_ s: CodeSessionStatus) -> String {
        switch s {
        case .running:    return "running"
        case .exited:     return "exited"
        case .error:      return "error"
        }
    }

    private static func macLabel() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    // MARK: - HTTP

    private var nexusBase: String { LumenAPIManager.shared.nexusBase }
    private var sessionCookie: String? { LumenAPIManager.shared.sessionCookie }

    @discardableResult
    private func postJSON(path: String, body: [String: Any], statusOK: Int = 200) async -> [String: Any]? {
        await sendJSON(method: "POST", path: path, body: body, expect: statusOK)
    }

    @discardableResult
    private func patchJSON(path: String, body: [String: Any]) async -> [String: Any]? {
        await sendJSON(method: "PATCH", path: path, body: body, expect: 200)
    }

    private func getJSON(path: String) async -> [String: Any]? {
        guard let cookie = sessionCookie, !cookie.isEmpty,
              let url = URL(string: nexusBase + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func sendJSON(method: String, path: String, body: [String: Any], expect: Int) async -> [String: Any]? {
        guard let cookie = sessionCookie, !cookie.isEmpty,
              let url = URL(string: nexusBase + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == expect else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } catch {
            return nil
        }
    }
}

// LumenAppRegistry receives a one-line hook to start the bridge once at
// app launch. Place this call after auth is restored so the first POST
// to /api/terminal/sessions has a valid Bearer cookie.
//
//   LumenTerminalBridge.shared.start(registry: appRegistry)
