import SwiftUI
import AppKit

extension Notification.Name {
    static let lumenCommandPaletteToggle = Notification.Name("lumen.commandPalette.toggle")
    static let lumenMentionTap           = Notification.Name("lumen.mention.tap")
}

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: LumenStore
    @StateObject private var auth: AuthManager
    @StateObject private var sync: LumenSync

    init() {
        let store = LumenStore()
        self._store = StateObject(wrappedValue: store)
        self._auth  = StateObject(wrappedValue: AuthManager())
        self._sync  = StateObject(wrappedValue: LumenSync(store: store))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if auth.isAuthenticated {
                    MainView()
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(sync)
                } else {
                    AuthGate()
                        .environmentObject(auth)
                }
            }
            .frame(minWidth: 1200, minHeight: 800)
            .task { await store.startup() }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
