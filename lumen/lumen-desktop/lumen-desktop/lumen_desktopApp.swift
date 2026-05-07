import SwiftUI
import AppKit

extension Notification.Name {
    static let lumenCommandPaletteToggle = Notification.Name("lumen.commandPalette.toggle")
    static let lumenMentionTap           = Notification.Name("lumen.mention.tap")
    static let lumenComposerFocus        = Notification.Name("lumen.composer.focus")
}

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: LumenStore
    @StateObject private var auth: AuthManager
    @StateObject private var sync: LumenSync
    @StateObject private var apps: LumenAppRegistry
    @StateObject private var authRegistry: LumenAuthRegistry

    init() {
        let store = LumenStore()
        let registry = LumenAppRegistry()
        let authReg = LumenAuthRegistry()
        let auth = AuthManager()
        // Wire the registry into AuthManager so any cookie that lands via
        // face/PIN/passphrase paths becomes a known multi-user session.
        auth.onCookieAdopted = { [weak authReg] cookie in
            Task { @MainActor in
                await authReg?.adoptFreshSession(cookie: cookie)
            }
        }
        auth.onSignOut = { [weak authReg] in
            Task { @MainActor in await authReg?.signOutActive() }
        }
        // When the active human flips (login, switch, restore), flush
        // per-user state in the store and refetch under the new cookie.
        // Also update Eve's system prompt to address the new user by name —
        // without this Eve would keep saying whatever name was baked in.
        authReg.onActiveHumanChanged = { [weak store] profile in
            let firstName = profile?.displayName.split(separator: " ").first.map(String.init) ?? "the user"
            LumenAPIManager.shared.activeUserFirstName = firstName
            // Skip the initial nil → restore case; switching away from a
            // valid user OR switching to a different valid user should both
            // flush. The store's reload guards an empty fetch result.
            if profile != nil { store?.reloadForActiveUserSwitch() }
        }
        self._store = StateObject(wrappedValue: store)
        self._auth  = StateObject(wrappedValue: auth)
        self._sync  = StateObject(wrappedValue: LumenSync(store: store))
        self._apps  = StateObject(wrappedValue: registry)
        self._authRegistry = StateObject(wrappedValue: authReg)
        AppDelegate.appRegistry = registry
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if auth.isAuthenticated {
                    MainView()
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(sync)
                        .environmentObject(apps)
                        .environmentObject(authRegistry)
                } else {
                    AuthGate()
                        .environmentObject(auth)
                        .environmentObject(authRegistry)
                }
            }
            .frame(minWidth: 1200, minHeight: 800)
            .task {
                // Pick localhost vs remote BEFORE any auth/data calls — without
                // this, every request goes to the default localhost:3000 which
                // strands the user on a "CONNECTION ERROR" if `next dev` isn't
                // running.
                _ = await LumenAPIManager.shared.resolveBaseURL()

                // Restore active session from Keychain BEFORE startup runs —
                // startup uses the cookie for its initial fetches.
                if await authRegistry.restoreActiveSession() {
                    auth.isAuthenticated = true
                }
                await store.startup()
            }
            .onChange(of: auth.isAuthenticated) { _, authenticated in
                if authenticated {
                    Task {
                        await store.fetchDashboard()
                        await store.fetchOperations()
                    }
                    sync.start()
                } else {
                    sync.stop()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            PanelCommands()
        }

        // Detached panel windows — any panel (agents, ops, directives, memory,
        // chats, files, system, settings) can be popped out into its own
        // native window. macOS Stage Manager / Mission Control treats each
        // as a separate window; user can drag to any monitor.
        WindowGroup(id: "panel", for: MainView.PanelType.self) { $type in
            DetachedPanelWindow(type: type ?? .none)
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(sync)
                .environmentObject(apps)
                .frame(minWidth: 720, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 720)

        WindowGroup("Operation", id: "operation-detail", for: String.self) { $operationId in
            OperationWindow(operationId: operationId ?? "")
                .environmentObject(store)
                .environmentObject(sync)
                .frame(minWidth: 900, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)

        // Per-agent detail windows
        WindowGroup("Agent", id: "agent-detail", for: String.self) { $agentId in
            AgentWindow(agentId: agentId ?? "")
                .environmentObject(store)
                .environmentObject(sync)
                .frame(minWidth: 720, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 740)

        // Per-conversation windows — Director can run several threads side
        // by side. Each window has its own send loop pinned to its conversationId.
        WindowGroup("Conversation", id: "conversation-detail", for: String.self) { $convId in
            ConversationWindow(conversationId: convId ?? "")
                .environmentObject(store)
                .environmentObject(sync)
                .frame(minWidth: 600, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 680)

        // Quick Capture — floating mini-window for drop-a-thought interactions.
        // Sends to Eve with full tool access, fades out after a brief reply.
        Window("Quick Capture", id: "quick-capture") {
            QuickCaptureWindow()
                .environmentObject(store)
                .environmentObject(auth)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.top)
        .defaultSize(width: 580, height: 240)

        // Eve orb popout — dedicated status window. Director can pin it to a
        // second monitor or floating-on-top while working in another app.
        Window("Eve", id: "eve-orb") {
            EveOrbWindow()
                .environmentObject(store)
                .environmentObject(auth)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .defaultSize(width: 380, height: 460)

        // Lumen Console — datasets / search / sync status. Reachable from
        // the Panels menu (Cmd-Opt-D). Surfaces what the local cache layer
        // is doing under the hood without us having to retrofit MainView.
        Window("Lumen Console", id: "lumen-console") {
            LumenConsoleWindow()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(auth)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 600)

        // Global search palette — Cmd-Shift-K opens it from anywhere.
        // Self-contained: the window dismisses itself when the palette
        // closes (selection or ESC).
        Window("Lumen Search", id: "lumen-search") {
            SearchWindow()
                .environmentObject(store)
                .environmentObject(sync)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 700, height: 580)

        // Menu bar item — Eve always available from the system menu bar.
        // Click the icon for a popover with status, last reply, and quick
        // jump-to-main-window. Useful when Lumen's main window is hidden.
        MenuBarExtra("Eve", systemImage: "brain") {
            MenuBarPopover()
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(sync)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu commands for opening detached panel windows

struct PanelCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Panels") {
            Button("Quick Capture…") {
                openWindow(id: "quick-capture")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Eve Orb Window") {
                openWindow(id: "eve-orb")
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            Button("Lumen Console…") {
                openWindow(id: "lumen-console")
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            Button("Search Everything…") {
                openWindow(id: "lumen-search")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Command Palette…") {
                NotificationCenter.default.post(name: .lumenCommandPaletteToggle, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
            Divider()
            Button("Agents")          { openWindow(id: "panel", value: MainView.PanelType.agents) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Operations")      { openWindow(id: "panel", value: MainView.PanelType.operations) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Directives")      { openWindow(id: "panel", value: MainView.PanelType.directives) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Memory Bank")     { openWindow(id: "panel", value: MainView.PanelType.memory) }
                .keyboardShortcut("4", modifiers: [.command, .option])
            Button("Conversations")   { openWindow(id: "panel", value: MainView.PanelType.chats) }
                .keyboardShortcut("5", modifiers: [.command, .option])
            Button("Nexus Map")       { openWindow(id: "panel", value: MainView.PanelType.nexusMap) }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Button("Files")           { openWindow(id: "panel", value: MainView.PanelType.files) }
                .keyboardShortcut("6", modifiers: [.command, .option])
            Button("System")          { openWindow(id: "panel", value: MainView.PanelType.system) }
                .keyboardShortcut("7", modifiers: [.command, .option])
            Button("Settings")        { openWindow(id: "panel", value: MainView.PanelType.settings) }
                .keyboardShortcut(",", modifiers: [.command, .shift])
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Static weak handle — App.init sets this so applicationWillTerminate
    /// can clean up child processes. Weak so the registry isn't kept alive
    /// past the App's StateObject lifetime.
    static weak var appRegistry: LumenAppRegistry?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Kill any in-flight Claude Code (or future) sessions before the
    /// process actually exits. Without this, PTY children become orphans
    /// reparented to launchd until they happen to read EOF.
    func applicationWillTerminate(_ notification: Notification) {
        // applicationWillTerminate runs on main, but @MainActor isolation
        // on the registry is established at the type level — call inside
        // a Task to satisfy the isolation requirement.
        let registry = AppDelegate.appRegistry
        Task { @MainActor in registry?.terminateAll() }
    }
}
