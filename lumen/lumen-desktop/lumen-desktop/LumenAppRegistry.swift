import Foundation
import AppKit
import Combine
import SwiftUI
import SwiftTerm

/// Registry of long-lived "app" sessions that live OUTSIDE the SwiftUI view
/// tree. The Director can navigate away from any panel and the running
/// processes (Claude Code terminals today, more app types tomorrow) keep
/// going — exactly like real apps on a real OS.
///
/// Why this layer exists:
///   The naive v0 of CodePanel created `LocalProcessTerminalView` inside an
///   NSViewRepresentable that lived in SwiftUI's view tree. Navigating away
///   tore the view down, deallocated the terminal NSView, and killed the
///   child process. By lifting session ownership to a registry held by the
///   App root, sessions survive every view-body recompute.
///
/// Future shape: when more app types arrive (web views, chart panels,
/// embedded editors, etc.), generalize via a `LumenApp` protocol with
/// `id`, `title`, `status`, and `view: NSView`. Single concrete
/// `CodeSession` is enough today (YAGNI).
@MainActor
final class LumenAppRegistry: ObservableObject {
    @Published private(set) var codeSessions: [CodeSession] = []

    /// Number of code sessions currently running (process not yet exited).
    /// Used by the sidebar/workspace card to render a live badge so the
    /// Director sees activity without having to open the panel.
    var runningCodeCount: Int { codeSessions.filter { $0.status.isRunning }.count }

    @discardableResult
    func startCodeSession(folder: String, claudePath: String) -> CodeSession {
        let session = CodeSession(folder: folder, claudePath: claudePath)
        codeSessions.append(session)
        return session
    }

    /// Terminate the underlying process and drop the registry's strong
    /// reference so the NSView/process can finally deallocate.
    func remove(_ session: CodeSession) {
        session.terminate()
        codeSessions.removeAll { $0.id == session.id }
    }

    /// Called from AppDelegate.applicationWillTerminate to make sure no
    /// orphan PTY child processes survive the app exit.
    func terminateAll() {
        for s in codeSessions { s.terminate() }
        codeSessions.removeAll()
    }
}

// MARK: - Code (Claude Code) session

enum CodeSessionStatus: Equatable {
    case running
    case exited(Int32?)
    case error(String)

    var isRunning: Bool { if case .running = self { return true }; return false }

    var label: String {
        switch self {
        case .running:           return "RUNNING"
        case .exited(let code):  return code == 0 ? "DONE" : "EXITED \(code.map(String.init) ?? "?")"
        case .error(let msg):    return "ERROR · \(msg.prefix(20))"
        }
    }
}

/// One Claude Code session — owns the SwiftTerm `LocalProcessTerminalView`
/// and the PTY child process for its entire lifetime. Held strongly by the
/// registry; the SwiftUI view layer only borrows a reference to embed.
@MainActor
final class CodeSession: ObservableObject, Identifiable {
    let id: UUID = UUID()
    let folder: String
    let claudePath: String
    let createdAt: Date = Date()

    @Published var title: String
    @Published var status: CodeSessionStatus = .running

    /// The persistent terminal NSView. Lives for the session's lifetime;
    /// gets re-parented between SwiftUI containers as the Director
    /// navigates around.
    let terminalView: LocalProcessTerminalView

    private let delegate: TerminalDelegate

    init(folder: String, claudePath: String) {
        self.folder = folder
        self.claudePath = claudePath
        self.title = (folder as NSString).lastPathComponent
        self.terminalView = LocalProcessTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        self.delegate = TerminalDelegate()
        self.terminalView.processDelegate = delegate
        delegate.bind(to: self)
        startProcess()
    }

    private func startProcess() {
        // Login shell so PATH/profile/env match a real Terminal session.
        // exec at the end of the inner command means the shell is replaced
        // by `claude` — when claude exits, the PTY child exits, our
        // delegate fires processTerminated, and we update status.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let inner = "cd \(Self.shellEscape(folder)) && exec \(Self.shellEscape(claudePath))"
        terminalView.startProcess(
            executable: shell,
            args: ["-l", "-c", inner],
            environment: nil,
            execName: nil
        )
    }

    func terminate() {
        // SwiftTerm's `process` is optional in this version. If it's still
        // alive, ask it to terminate; if not, the child has already exited.
        // The registry drops its reference after this returns and the
        // NSView tears down on the next runloop tick.
        terminalView.process?.terminate()
        if case .running = status { status = .exited(nil) }
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Delegate is a class so SwiftTerm can hold a weak reference and so we
    // can re-bind to a session after init (closures can't be init-time
    // forward references on an actor-isolated class).
    fileprivate final class TerminalDelegate: NSObject, LocalProcessTerminalViewDelegate {
        weak var session: CodeSession?

        func bind(to session: CodeSession) { self.session = session }

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [weak self] in
                guard let s = self?.session, !title.isEmpty else { return }
                s.title = title
            }
        }
        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.session?.status = .exited(exitCode)
            }
        }
    }
}

// MARK: - Persistent terminal embed

/// Re-parents an existing `LocalProcessTerminalView` (owned by a
/// `CodeSession` in the registry) into the SwiftUI view tree without
/// creating or destroying the underlying NSView. When this representable
/// is dismounted (Director navigates away), the terminal goes back to
/// being parent-less BUT remains alive thanks to the registry's strong
/// reference. Mounting elsewhere just re-adds it as a subview.
struct SessionTerminalHost: NSViewRepresentable {
    let session: CodeSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizingMask = [.width, .height]
        attach(session.terminalView, to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // If the active session changed, swap the embedded subview.
        let current = container.subviews.first
        if current !== session.terminalView {
            current?.removeFromSuperview()
            attach(session.terminalView, to: container)
        }
    }

    private func attach(_ view: NSView, to container: NSView) {
        // The NSView may still be a subview of a previous container that
        // SwiftUI hasn't torn down yet. Detach first so we never violate
        // "an NSView has at most one superview at a time."
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
