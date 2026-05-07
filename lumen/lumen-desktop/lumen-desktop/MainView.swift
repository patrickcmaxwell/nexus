import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Color palette

// Lumen palette. Accents (eve / listen / think / danger) are constant in
// both modes — they read fine on light or dark surfaces. The neutrals
// (bg, surface, surfaceHi, hairline) are AppKit-dynamic so they actually
// flip when the user's macOS is on Auto/Light. Foreground text uses
// `.primary` and `.secondary` semantic colors elsewhere; this enum carries
// only the brand chrome.
enum C {
    // Accents — same in light and dark
    static let eve    = Color(red: 0.545, green: 0.361, blue: 0.965) // violet — Eve's identity
    static let listen = Color(red: 0.20,  green: 0.78,  blue: 0.40)  // emerald green
    static let think  = Color(red: 0.95,  green: 0.65,  blue: 0.0)   // amber
    static let danger = Color(red: 0.95,  green: 0.25,  blue: 0.25)  // red

    // Adaptive neutrals
    static let bg = Color(nsColor: NSColor(name: "lumen.bg") { app in
        app.isDark ? NSColor(red: 0.028, green: 0.028, blue: 0.056, alpha: 1)
                   : NSColor(red: 0.97,  green: 0.97,  blue: 0.99,  alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: "lumen.surface") { app in
        app.isDark ? NSColor(red: 0.055, green: 0.06,  blue: 0.11,  alpha: 1)
                   : NSColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 1)
    })
    static let surfaceHi = Color(nsColor: NSColor(name: "lumen.surfaceHi") { app in
        app.isDark ? NSColor(red: 0.065, green: 0.07,  blue: 0.11,  alpha: 1)
                   : NSColor(red: 0.96,  green: 0.96,  blue: 0.98,  alpha: 1)
    })
    static let hairline = Color(nsColor: NSColor(name: "lumen.hairline") { app in
        app.isDark ? NSColor(white: 1.0, alpha: 0.05)
                   : NSColor(white: 0.0, alpha: 0.06)
    })
    static let dim = Color(nsColor: NSColor(name: "lumen.dim") { app in
        app.isDark ? NSColor(white: 1.0, alpha: 0.55)
                   : NSColor(white: 0.0, alpha: 0.62)
    })
}

private extension NSAppearance {
    /// True when the active appearance is one of the dark variants.
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
    }
}

// MARK: - Root view

struct MainView: View {
    @EnvironmentObject var store: LumenStore
    @EnvironmentObject var auth: AuthManager

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var showLauncher = false
    @State private var activePanel: PanelType = .none
    @State private var lmStatus: LMStatus = .checking
    @SceneStorage("lumen.shell.canvasWidth") private var canvasWidth: Double = 430
    @SceneStorage("lumen.shell.canvasCollapsed") private var canvasCollapsed = false
    @SceneStorage("lumen.shell.canvasTakeover") private var canvasTakeover = false
    @SceneStorage("lumen.shell.quickChatVisible") private var quickChatVisible = false
    @SceneStorage("lumen.shell.quickChatWidth") private var quickChatWidth: Double = 500
    @SceneStorage("lumen.shell.quickChatHeight") private var quickChatHeight: Double = 360
    @SceneStorage("lumen.shell.quickChatExpanded") private var quickChatExpanded = false
    @State private var railHovered = false
    @State private var railPinned = false
    @State private var railCollapseWorkItem: DispatchWorkItem?

    static func panelFor(mentionType type: String) -> PanelType {
        switch type {
        case "operation", "record": return .operations
        case "agent":               return .agents
        case "conversation":        return .chats
        case "memory":              return .memory
        case "directive":           return .directives
        default:                    return .none
        }
    }

    enum PanelType: String, Codable, Hashable, Equatable, CaseIterable, Identifiable {
        case none, agents, operations, directives, memory, chats, nexusMap = "nexus_map", files, code, system, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none:       return "Eve"
            case .agents:     return "Agents"
            case .operations: return "Operations"
            case .directives: return "Directives"
            case .memory:     return "Memory Bank"
            case .chats:      return "Conversations"
            case .nexusMap:   return "Nexus Map"
            case .files:      return "Files"
            case .code:       return "Code"
            case .system:     return "System"
            case .settings:   return "Settings"
            }
        }
    }

    enum LMStatus {
        case checking, online(String), offline
        var isOnline: Bool { if case .online = self { return true }; return false }
        var label: String {
            switch self {
            case .checking:        return "CHECKING"
            case .offline:         return "LM OFFLINE"
            case .online(let m):   return m.isEmpty ? "LM ONLINE" : m.prefix(18).uppercased()
            }
        }
    }

    var body: some View {
        ZStack {
            BackgroundLayer()

            WorkspaceRootShell(
                activePanel: $activePanel,
                store: store,
                auth: auth,
                lmStatus: lmStatus,
                inputText: $inputText,
                inputFocused: $inputFocused,
                canvasWidth: $canvasWidth,
                canvasCollapsed: $canvasCollapsed,
                canvasTakeover: $canvasTakeover,
                quickChatVisible: $quickChatVisible,
                quickChatWidth: $quickChatWidth,
                quickChatHeight: $quickChatHeight,
                quickChatExpanded: $quickChatExpanded,
                railHovered: $railHovered,
                railPinned: $railPinned,
                onRailHoverChanged: updateRailHover,
                onSubmit: submitInput
            )
        }
        .overlay {
            if store.commandPaletteVisible {
                CommandPaletteOverlay(activePanel: $activePanel)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumenCommandPaletteToggle)) { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                store.commandPaletteVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumenMentionTap)) { note in
            guard let info = note.userInfo,
                  let type = info["type"] as? String else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                activePanel = MainView.panelFor(mentionType: type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumenComposerFocus)) { _ in
            // Triggered when a context-menu action (e.g. "Reply to this")
            // wants the composer to grab focus immediately.
            inputFocused = true
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activePanel)
        .task {
            await store.fetchDashboard()
            await store.fetchOperations()
            await pingLMStudio()
        }
    }

    private func submitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // If the Director picked "Reply" off an Eve message, prepend the
        // quoted blockquote so Eve sees what's being responded to. Consuming
        // the prefix also clears the pinned reply target.
        let prefix = store.consumeReplyPrefix()
        let outgoing = prefix + trimmed
        inputText = ""
        Task { await store.send(outgoing) }
    }

    private func pingLMStudio() async {
        // Probes the local LLM (Ollama on :11434, OpenAI-compatible /v1/models).
        // Function name kept for compatibility with surrounding state plumbing.
        guard let url = URL(string: "http://localhost:11434/v1/models") else { lmStatus = .offline; return }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { lmStatus = .offline; return }
            if let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models  = json["data"] as? [[String: Any]],
               let first   = models.first,
               let modelId = first["id"] as? String {
                lmStatus = .online(modelId)
            } else {
                lmStatus = .online("")
            }
        } catch {
            lmStatus = .offline
        }
    }

    private func updateRailHover(_ isHovering: Bool) {
        railCollapseWorkItem?.cancel()
        if isHovering {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.18)) {
                railHovered = true
            }
            return
        }

        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.92, blendDuration: 0.16)) {
                railHovered = false
            }
        }
        railCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }
}

struct WorkspaceRootShell: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    @Binding var canvasWidth: Double
    @Binding var canvasCollapsed: Bool
    @Binding var canvasTakeover: Bool
    @Binding var quickChatVisible: Bool
    @Binding var quickChatWidth: Double
    @Binding var quickChatHeight: Double
    @Binding var quickChatExpanded: Bool
    @Binding var railHovered: Bool
    @Binding var railPinned: Bool
    let onRailHoverChanged: (Bool) -> Void
    let onSubmit: () -> Void

    @Environment(\.openWindow) private var openWindow

    private var railExpanded: Bool { railPinned || railHovered }
    private var hasConversationWindow: Bool { store.currentConversationId != nil }
    private var showingWorkspacePanel: Bool { activePanel != .none }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width - (railExpanded ? 252 : 130)
            let clampedWidth = max(360, min(CGFloat(canvasWidth), max(availableWidth * 0.7, 420)))
            let canvasVisible = !canvasCollapsed
            let assistantWidth = max(360, min(CGFloat(canvasWidth), 520))
            let quickWidth = quickChatExpanded
                ? min(max(proxy.size.width * 0.72, 760), proxy.size.width - 72)
                : min(max(CGFloat(quickChatWidth), 420), min(proxy.size.width - 32, 920))
            let quickHeight = quickChatExpanded
                ? min(max(proxy.size.height * 0.82, 520), proxy.size.height - 44)
                : min(max(CGFloat(quickChatHeight), 320), min(proxy.size.height - 28, 760))

            HStack(spacing: 10) {
                CommandRail(
                    activePanel: $activePanel,
                    store: store,
                    expanded: railExpanded,
                    pinned: $railPinned,
                    onToggleCanvas: {
                        if showingWorkspacePanel {
                            if canvasCollapsed {
                                quickChatVisible.toggle()
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    canvasCollapsed = true
                                    quickChatVisible = false
                                }
                            }
                        } else if canvasCollapsed {
                            canvasCollapsed = false
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                canvasCollapsed = true
                            }
                        }
                    }
                )
                .frame(width: railExpanded ? 196 : 74)
                .animation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.18), value: railExpanded)
                .onHover(perform: onRailHoverChanged)

                VStack(spacing: 10) {
                    WorkspaceHeader(
                        store: store,
                        activePanel: $activePanel,
                        canvasCollapsed: $canvasCollapsed,
                        canvasTakeover: $canvasTakeover,
                        quickChatVisible: $quickChatVisible,
                        hasConversationWindow: hasConversationWindow,
                        onOpenConversationWindow: openConversationWindow
                    )

                    HStack(spacing: 8) {
                        primarySurface
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)

                        if !showingWorkspacePanel && canvasVisible {
                            CanvasResizeHandle(width: $canvasWidth)
                            AdaptiveCanvasSurface(
                                activePanel: $activePanel,
                                store: store,
                                auth: auth,
                                inputText: $inputText,
                                inputFocused: $inputFocused,
                                onSubmit: onSubmit
                            )
                            .frame(width: canvasTakeover ? max(clampedWidth, availableWidth * 0.56) : clampedWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else if showingWorkspacePanel && canvasVisible {
                            CanvasResizeHandle(width: $canvasWidth)
                            AssistantDrawer(
                                store: store,
                                inputText: $inputText,
                                inputFocused: $inputFocused,
                                expanded: $canvasTakeover,
                                onSubmit: onSubmit,
                                onPopOut: openConversationWindow,
                                onClose: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                        canvasCollapsed = true
                                    }
                                }
                            )
                            .frame(width: assistantWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                if showingWorkspacePanel && canvasCollapsed {
                    if quickChatVisible {
                        QuickChatOverlay(
                            store: store,
                            inputText: $inputText,
                            inputFocused: $inputFocused,
                            width: $quickChatWidth,
                            height: $quickChatHeight,
                            expanded: $quickChatExpanded,
                            onSubmit: onSubmit,
                            onPopOut: openConversationWindow,
                            onClose: { quickChatVisible = false }
                        )
                        .frame(width: quickWidth, height: quickHeight)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                quickChatVisible = true
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Open Chat")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(C.eve)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(C.eve.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var primarySurface: some View {
        Group {
            if showingWorkspacePanel {
                WorkspacePanelSurface(
                    activePanel: $activePanel,
                    store: store,
                    auth: auth
                )
            } else {
                if store.viewMode == .dashboard {
                    DashboardView(
                        store: store,
                        auth: auth,
                        lmStatus: lmStatus,
                        inputText: $inputText,
                        inputFocused: $inputFocused
                    )
                } else {
                    LiveThreadView(
                        store: store,
                        inputText: $inputText,
                        inputFocused: $inputFocused,
                        onSubmit: onSubmit
                    )
                }
            }
        }
        .background(WorkspaceSurfaceCard(material: .ultraThinMaterial, cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func popOutActivePanel() {
        guard activePanel != .none else { return }
        openWindow(id: "panel", value: activePanel)
    }

    private func openConversationWindow() {
        guard let cid = store.currentConversationId else { return }
        openWindow(id: "conversation-detail", value: cid)
    }
}

private struct WorkspaceHeader: View {
    @ObservedObject var store: LumenStore
    @Binding var activePanel: MainView.PanelType
    @Binding var canvasCollapsed: Bool
    @Binding var canvasTakeover: Bool
    @Binding var quickChatVisible: Bool
    let hasConversationWindow: Bool
    let onOpenConversationWindow: () -> Void

    private var eyebrow: String {
        activePanel == .none ? (store.viewMode == .dashboard ? "MISSION CONTROL" : "LIVE CHAT") : activePanel.title.uppercased()
    }

    private var title: String {
        if activePanel != .none {
            return activePanel.title
        }
        if store.viewMode == .dashboard {
            return "Nexus Workspace"
        }
        return store.currentConversationTitle ?? "Live Session"
    }

    private var detail: String {
        if activePanel != .none {
            return "This workspace owns the main window. Keep chat docked, hide it, or pop it up from the bottom when you need Eve."
        }
        if store.viewMode == .dashboard {
            return "Overview first. Open datasets and companion workspaces as needed."
        }
        return "Chat remains primary while the canvas can inspect operations, code, files, and system surfaces."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(C.eve.opacity(0.9))
                    .tracking(2.8)
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.94))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                EveStatusToolbar(store: store)
                GlobalVoiceToolbar(store: store)
                if hasConversationWindow {
                    WorkspaceHeaderButton(icon: "rectangle.on.rectangle", label: "Pop Out Chat", tint: C.eve, action: onOpenConversationWindow)
                }
                WorkspaceHeaderButton(
                    icon: canvasCollapsed ? "sidebar.right" : "sidebar.right",
                    label: activePanel == .none
                        ? (canvasCollapsed ? "Show Canvas" : "Hide Canvas")
                        : (canvasCollapsed ? "Quick Chat" : "Hide Chat"),
                    tint: C.listen,
                    action: {
                        if activePanel == .none {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                canvasCollapsed.toggle()
                                if canvasCollapsed {
                                    canvasTakeover = false
                                }
                            }
                        } else if canvasCollapsed {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                quickChatVisible.toggle()
                            }
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                canvasCollapsed = true
                            }
                        }
                    }
                )
                if !canvasCollapsed && activePanel == .none {
                    WorkspaceHeaderButton(
                        icon: canvasTakeover ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        label: canvasTakeover ? "Balanced View" : "Canvas Takeover",
                        tint: C.think,
                        action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                canvasTakeover.toggle()
                            }
                        }
                    )
                }
                UserAvatarMenu()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(WorkspaceSurfaceCard(material: .ultraThinMaterial, cornerRadius: 20))
    }
}

private struct CommandRail: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    let expanded: Bool
    @Binding var pinned: Bool
    let onToggleCanvas: () -> Void
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var apps: LumenAppRegistry

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Button(action: { pinned.toggle() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(C.eve.opacity(0.12))
                        Image(systemName: pinned ? "pin.fill" : "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(C.eve)
                    }
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin command rail" : "Pin command rail open")

                Text("NEXUS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(C.eve.opacity(0.88))
                    .tracking(3)
                    .frame(height: 14)
                    .opacity(expanded ? 1 : 0)
                    .offset(y: expanded ? 0 : -6)
                    .blur(radius: expanded ? 0 : 2)
            }

            VStack(spacing: 8) {
                railButton(.none, label: "Live", icon: "waveform.circle.fill", tint: C.eve)
                railButton(.operations, label: "Operations", icon: "bolt.circle.fill", tint: C.think, badge: store.operations.count)
                railButton(.agents, label: "Agents", icon: "person.3.fill", tint: C.listen, badge: store.agents.count)
                railButton(.chats, label: "Chats", icon: "bubble.left.and.bubble.right.fill", tint: C.eve, badge: store.conversations.count)
                railButton(.code, label: "Code", icon: "terminal.fill", tint: apps.runningCodeCount > 0 ? C.listen : C.eve, badge: apps.runningCodeCount > 0 ? apps.runningCodeCount : nil)
                railButton(.files, label: "Files", icon: "folder.fill", tint: C.eve)
                railButton(.nexusMap, label: "Map", icon: "globe", tint: C.eve)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: onToggleCanvas) {
                    RailCapsule(icon: "sidebar.trailing", label: "Canvas", tint: C.listen, isSelected: false, expanded: expanded)
                }
                .buttonStyle(.plain)
                .help("Toggle adaptive canvas")

                railButton(.system, label: "System", icon: "cpu.fill", tint: C.listen)
                railButton(.settings, label: "Settings", icon: "gearshape.fill", tint: C.think)
            }
        }
        .padding(.horizontal, expanded ? 12 : 8)
        .padding(.vertical, 16)
        .background(WorkspaceSurfaceCard(material: .ultraThinMaterial, cornerRadius: 22))
        .animation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.18), value: expanded)
    }

    private func railButton(_ panel: MainView.PanelType, label: String, icon: String, tint: Color, badge: Int? = nil) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                if panel == .none {
                    activePanel = .none
                } else {
                    activePanel = activePanel == panel ? .none : panel
                }
            }
        }) {
            RailCapsule(
                icon: icon,
                label: label,
                tint: tint,
                isSelected: activePanel == panel || (panel == .none && activePanel == .none),
                badge: badge,
                expanded: expanded
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in New Window") {
                openWindow(id: "panel", value: panel)
            }
        }
        .help(label)
    }
}

private struct RailCapsule: View {
    let icon: String
    let label: String
    let tint: Color
    let isSelected: Bool
    var badge: Int? = nil
    var expanded: Bool = false

    var body: some View {
        Group {
            if expanded {
                HStack(spacing: 10) {
                    iconBlock

                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? tint : .secondary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                iconBlock
            }
        }
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? tint.opacity(0.12) : Color.clear)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.9, blendDuration: 0.14), value: expanded)
    }

    private var iconBlock: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? tint : .secondary.opacity(0.7))
            .frame(width: 42, height: 42)
            .contentShape(Rectangle())
    }
}

private struct SoftRowSurface: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.10) : isHovered ? Color.white.opacity(0.04) : Color.clear)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

private extension View {
    func softRowSurface(isSelected: Bool, isHovered: Bool, accent: Color) -> some View {
        modifier(SoftRowSurface(isSelected: isSelected, isHovered: isHovered, accent: accent))
    }
}

private struct AdaptiveCanvasSurface: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        ContextualCanvasView(activePanel: $activePanel, store: store)
        .background(WorkspaceSurfaceCard(material: .ultraThinMaterial, cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct WorkspacePanelSurface: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager

    var body: some View {
        Group {
            switch activePanel {
            case .none:
                EmptyView()
            case .chats:
                ChatsPanel(store: store) { activePanel = .none }
            case .agents:
                AgentPanel(store: store) { activePanel = .none }
            case .operations:
                OpsPanel2(store: store) { activePanel = .none }
            case .directives:
                DirectivesPanel(store: store) { activePanel = .none }
            case .memory:
                MemoryPanel(store: store) { activePanel = .none }
            case .nexusMap:
                NexusMapView(store: store)
            case .files:
                FilesPanel(store: store) { activePanel = .none }
            case .code:
                CodePanel(store: store) { activePanel = .none }
            case .system:
                SystemPanel(store: store) { activePanel = .none }
            case .settings:
                SettingsPanel(store: store, auth: auth) { activePanel = .none }
            }
        }
    }
}

private struct AssistantDrawer: View {
    @ObservedObject var store: LumenStore
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    @Binding var expanded: Bool
    let onSubmit: () -> Void
    let onPopOut: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("ASSISTANT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(C.eve.opacity(0.88))
                    .tracking(2)
                Spacer()
                WorkspaceHeaderButton(
                    icon: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: expanded ? "Standard" : "Expand",
                    tint: C.listen
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        expanded.toggle()
                    }
                }
                WorkspaceHeaderButton(icon: "rectangle.on.rectangle", label: "Pop Out", tint: C.eve, action: onPopOut)
                WorkspaceHeaderButton(icon: "xmark", label: "Hide", tint: .secondary, action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.03))

            LiveThreadView(
                store: store,
                inputText: $inputText,
                inputFocused: $inputFocused,
                onSubmit: onSubmit
            )
        }
        .background(WorkspaceSurfaceCard(material: .ultraThinMaterial, cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct QuickChatOverlay: View {
    @ObservedObject var store: LumenStore
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    @Binding var width: Double
    @Binding var height: Double
    @Binding var expanded: Bool
    let onSubmit: () -> Void
    let onPopOut: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("EVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(C.eve.opacity(0.88))
                        .tracking(2)
                    Text(expanded ? "Expanded quick chat" : "Bottom assistant window")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleExpanded) {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(C.listen)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
                Button(action: onPopOut) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(C.eve)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.03))

            LiveThreadView(
                store: store,
                inputText: $inputText,
                inputFocused: $inputFocused,
                onSubmit: onSubmit
            )

            HStack {
                Text(expanded ? "Expanded" : "Drag to resize")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Spacer()
                QuickChatResizeHandle(width: $width, height: $height, isExpanded: expanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.025))
        }
        .background(WorkspaceSurfaceCard(material: .ultraThinMaterial, cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
        .onAppear {
            if width < 420 { width = 500 }
            if height < 320 { height = 360 }
        }
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            expanded.toggle()
        }
    }
}

private struct ContextualCanvasView: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    @EnvironmentObject var apps: LumenAppRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.viewMode == .dashboard ? "ADAPTIVE CANVAS" : "LIVE CONTEXT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(C.eve.opacity(0.88))
                        .tracking(2.5)
                    Text(store.viewMode == .dashboard ? "Overview with fast pivots into the active workspace." : "Conversation-linked surfaces stay one action away.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    CanvasMetricCard(title: "Operations", value: "\(store.operations.count)", detail: "Open the full operations dataset", tint: C.think) { activePanel = .operations }
                    CanvasMetricCard(title: "Agents", value: "\(store.agents.count)", detail: "Inspect active and standby units", tint: C.listen) { activePanel = .agents }
                    CanvasMetricCard(title: "Code", value: apps.runningCodeCount > 0 ? "\(apps.runningCodeCount)" : "Ready", detail: "Claude Code sessions and companion workspaces", tint: apps.runningCodeCount > 0 ? C.listen : C.eve) { activePanel = .code }
                    CanvasMetricCard(title: "Files", value: "Local", detail: "Evaluate source files and folders", tint: C.eve) { activePanel = .files }
                }

                ContextFocusCard(
                    title: store.currentConversationTitle ?? "No active thread",
                    subtitle: store.viewMode == .dashboard
                        ? "Start a live conversation and the canvas will pivot to the related operation, code session, or dataset."
                        : "Keep chat primary, then open related operations, code, files, or chats without losing the current thread.",
                    primaryLabel: "Open Conversations",
                    primaryAction: { activePanel = .chats },
                    secondaryLabel: "Open System",
                    secondaryAction: { activePanel = .system }
                )

                if let latest = store.messages.last {
                    ContextDataCard(title: "Latest Exchange", accent: C.eve) {
                        Text(latest.content)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .lineLimit(8)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct CanvasMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .tracking(1.8)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.92))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ContextFocusCard: View {
    let title: String
    let subtitle: String
    let primaryLabel: String
    let primaryAction: () -> Void
    let secondaryLabel: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CURRENT FOCUS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(C.eve.opacity(0.88))
                .tracking(2)
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                PanelActionButton(label: primaryLabel.uppercased(), color: C.eve, disabled: false, action: primaryAction)
                PanelActionButton(label: secondaryLabel.uppercased(), color: C.listen, disabled: false, action: secondaryAction)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ContextDataCard<Content: View>: View {
    let title: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.8)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CanvasResizeHandle: View {
    @Binding var width: Double
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .contentShape(Rectangle())
            .overlay(
                Capsule()
                    .fill(isHovered ? C.eve.opacity(0.25) : Color.white.opacity(0.04))
                    .frame(width: isHovered ? 3 : 1.5)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            )
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        width = max(360, min(900, width - Double(value.translation.width)))
                    }
            )
    }
}

private struct QuickChatResizeHandle: View {
    @Binding var width: Double
    @Binding var height: Double
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isExpanded ? .secondary.opacity(0.4) : C.eve.opacity(0.82))
        }
        .frame(width: 28, height: 28)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard !isExpanded else { return }
                    width = max(420, min(920, width + Double(value.translation.width)))
                    height = max(320, min(760, height - Double(value.translation.height)))
                }
        )
    }
}

private struct WorkspaceHeaderButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceSurfaceCard: View {
    let material: Material
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(material)
            .shadow(color: Color.black.opacity(0.08), radius: 32, y: 10)
    }
}

// MARK: - Sidebar (native vibrancy, single column of section-grouped items)

struct SidebarNav: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @Binding var activePanel: MainView.PanelType
    @EnvironmentObject var sync: LumenSync
    @EnvironmentObject var apps: LumenAppRegistry
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: Binding(
            get: { activePanel },
            set: { activePanel = $0 ?? .none }
        )) {
            Section {
                row(.none, label: "Live", icon: "waveform.circle.fill", tint: C.eve)
                row(.chats, label: "Conversations", icon: "bubble.left.and.bubble.right.fill", tint: C.eve, badge: store.conversations.count)
            }

            Section("Workspace") {
                row(.agents, label: "Agents", icon: "person.3.fill", tint: C.listen, badge: store.agents.count)
                row(.operations, label: "Operations", icon: "bolt.fill", tint: C.think, badge: store.operations.count)
                row(.directives, label: "Directives", icon: "shield.lefthalf.filled", tint: C.eve, badge: store.directives.count)
                row(.memory, label: "Memory", icon: "brain.head.profile", tint: C.listen, badge: store.memories.count)
                row(.nexusMap, label: "Nexus Map", icon: "globe", tint: C.eve)
                    .onTapGesture {
                        activePanel = .nexusMap
                        sync.mapDidOpen()
                        if store.nexusMap.nodes.isEmpty {
                            Task { await store.fetchNexusMap() }
                        }
                    }
            }

            Section("System") {
                row(.files, label: "Files", icon: "folder.fill", tint: C.eve)
                // Code badge tracks running Claude Code sessions live — the
                // Director sees activity without having to open the panel.
                row(.code, label: "Code", icon: "terminal.fill", tint: C.eve,
                    badge: apps.runningCodeCount > 0 ? apps.runningCodeCount : nil,
                    badgeIsLive: true)
                row(.system, label: "System", icon: "cpu.fill", tint: C.listen)
                row(.settings, label: "Settings", icon: "gearshape.fill", tint: C.think)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter(store: store, lmStatus: lmStatus)
        }
    }

    @ViewBuilder
    private func row(_ panel: MainView.PanelType, label: String, icon: String, tint: Color,
                     badge: Int? = nil, badgeIsLive: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
            Spacer()
            if let badge, badge > 0 {
                if badgeIsLive {
                    // Live activity dot + count — signals "something is
                    // running in the background you may have forgotten."
                    HStack(spacing: 4) {
                        Circle().fill(C.listen).frame(width: 6, height: 6)
                            .shadow(color: C.listen, radius: 3)
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(C.listen)
                    }
                } else {
                    Text("\(badge)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tag(panel)
        .contextMenu {
            Button("Open in New Window") {
                openWindow(id: "panel", value: panel)
            }
        }
    }
}

private struct SidebarFooter: View {
    @ObservedObject var store: LumenStore
    let lmStatus: MainView.LMStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(lmStatus.isOnline ? C.listen : Color.secondary)
                .frame(width: 7, height: 7)
            Text(lmStatus.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("EVE \(store.eveStatus.label.uppercased())")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(store.eveStatus.color)
                .tracking(1.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Detail container

struct DetailContainer: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        Group {
            switch activePanel {
            case .none:
                // Default surface routes through viewMode: dashboard is the
                // new landing, live is the chat thread the Director engages
                // into. Other panel selections (chats, agents, etc.) bypass
                // viewMode entirely and show their dedicated panel.
                if store.viewMode == .dashboard {
                    DashboardView(
                        store: store,
                        auth: auth,
                        lmStatus: lmStatus,
                        inputText: $inputText,
                        inputFocused: $inputFocused
                    )
                } else {
                    LiveThreadView(
                        store: store,
                        inputText: $inputText,
                        inputFocused: $inputFocused,
                        onSubmit: onSubmit
                    )
                }
            case .chats:
                ChatsPanel(store: store) { activePanel = .none }
            case .agents:
                AgentPanel(store: store) { activePanel = .none }
            case .operations:
                OpsPanel2(store: store) { activePanel = .none }
            case .directives:
                DirectivesPanel(store: store) { activePanel = .none }
            case .memory:
                MemoryPanel(store: store) { activePanel = .none }
            case .nexusMap:
                NexusMapView(store: store)
            case .files:
                FilesPanel(store: store) { activePanel = .none }
            case .code:
                CodePanel(store: store) { activePanel = .none }
            case .system:
                SystemPanel(store: store) { activePanel = .none }
            case .settings:
                SettingsPanel(store: store, auth: auth) { activePanel = .none }
            }
        }
        .navigationTitle(activePanel.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    EveStatusToolbar(store: store)
                    UserAvatarMenu()
                }
            }
        }
    }
}

// MARK: - Multi-user avatar menu

/// Top-bar avatar showing the active human's initial. Tap → menu with the
/// active user's identity, list of other known sessions on this device,
/// "Add another user" to launch a fresh auth, and "Sign Out".
private struct UserAvatarMenu: View {
    @EnvironmentObject var authRegistry: LumenAuthRegistry
    @EnvironmentObject var auth: AuthManager
    @State private var switchTargetEmail: String? = nil

    var body: some View {
        Menu {
            if let active = authRegistry.activeHuman {
                Section {
                    Text(active.displayName)
                    Text(active.email).font(.caption)
                    Text("\(active.role.uppercased())\(active.isOwner ? " · OWNER" : "")")
                        .font(.caption2)
                }
            }

            // Other known sessions — switching requires PIN re-verify
            let others = authRegistry.knownSessions.filter { $0.humanId != authRegistry.activeHuman?.humanId }
            if !others.isEmpty {
                Section("Switch User") {
                    ForEach(others) { session in
                        Button {
                            switchTargetEmail = session.email
                        } label: {
                            Label("\(session.displayName) · \(session.email)", systemImage: "person.crop.circle")
                        }
                    }
                }
            }

            Section {
                Button {
                    // Sign out the active user. AuthManager.signOut also calls
                    // onSignOut → LumenAuthRegistry.signOutActive() so the
                    // Keychain entry is dropped and AuthGate reappears.
                    auth.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button {
                    // "Add another user" — server-side logout invalidates the
                    // current cookie, then routing back to AuthGate lets the
                    // Director PIN/face into a different account. The prior
                    // session stays in Keychain so they can switch back later.
                    Task { @MainActor in
                        auth.signOut()
                    }
                } label: {
                    Label("Add Another User", systemImage: "person.badge.plus")
                }
            }
        } label: {
            avatarLabel
        }
        .menuStyle(.borderlessButton)
        .frame(width: 30, height: 30)
        .sheet(item: Binding(
            get: { switchTargetEmail.map { SwitchTarget(email: $0) } },
            set: { switchTargetEmail = $0?.email }
        )) { target in
            SwitchUserSheet(targetEmail: target.email) { switchTargetEmail = nil }
        }
    }

    @ViewBuilder
    private var avatarLabel: some View {
        let active = authRegistry.activeHuman
        ZStack {
            Circle()
                .fill(active?.isOwner == true ? C.eve.opacity(0.25) : C.surfaceHi)
            Circle()
                .stroke(active?.isOwner == true ? C.eve.opacity(0.5) : C.hairline, lineWidth: 1)
            Text(active?.avatarInitial ?? "?")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(active?.isOwner == true ? C.eve : .primary.opacity(0.7))
        }
        .frame(width: 28, height: 28)
        .help(active.map { "\($0.displayName) · \($0.role)" } ?? "Not signed in")
    }
}

/// `Identifiable` wrapper so we can drive a `.sheet(item:)` off an optional
/// email string without rolling our own state.
private struct SwitchTarget: Identifiable {
    var id: String { email }
    let email: String
}

/// PIN re-verify sheet that fires when the Director picks a different known
/// user from the avatar menu. Calls `LumenAuthRegistry.switchUser` which
/// hits `/api/auth/switch` — the server invalidates the current session
/// and issues a fresh one for the target human.
private struct SwitchUserSheet: View {
    let targetEmail: String
    let onDismiss: () -> Void

    @EnvironmentObject var authRegistry: LumenAuthRegistry
    @State private var pin = ""
    @State private var status: Status = .idle
    @State private var errorMsg = ""
    @FocusState private var pinFocused: Bool

    enum Status { case idle, loading, error }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Switch User").font(.system(size: 16, weight: .semibold))
                Text("Enter PIN for \(targetEmail)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count
                              ? (status == .error ? C.danger : C.eve)
                              : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
            }

            if status == .error {
                Text(errorMsg).font(.system(size: 10)).foregroundColor(C.danger)
            } else if status == .loading {
                Text("Switching…").font(.system(size: 10)).foregroundColor(C.eve)
            }

            HStack(spacing: 10) {
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.bordered)
            }

            // Hidden text field captures keyboard input
            TextField("", text: Binding(
                get: { pin },
                set: { newValue in
                    guard status != .loading else { return }
                    let digits = newValue.filter(\.isNumber)
                    pin = String(digits.prefix(4))
                    if pin.count == 4 { Task { await submit() } }
                }
            ))
            .textFieldStyle(.plain)
            .focused($pinFocused)
            .opacity(0.001)
            .frame(width: 1, height: 1)
        }
        .padding(28)
        .frame(width: 280, height: 220)
        .onAppear { pinFocused = true }
    }

    private func submit() async {
        status = .loading
        do {
            try await authRegistry.switchUser(toEmail: targetEmail, pin: pin)
            onDismiss()
        } catch {
            status = .error
            errorMsg = "Invalid PIN"
            pin = ""
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            status = .idle
        }
    }
}

private struct EveStatusToolbar: View {
    @ObservedObject var store: LumenStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.eveStatus.color)
                .frame(width: 7, height: 7)
                .shadow(color: store.eveStatus.color, radius: 4)
            Text(store.eveStatus.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct GlobalVoiceToolbar: View {
    @ObservedObject var store: LumenStore

    private var isListening: Bool {
        store.fluidListening || store.eveStatus == .listening
    }

    private var isSpeaking: Bool {
        store.eveStatus == .speaking
    }

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton(
                icon: isListening ? "mic.fill" : "mic",
                label: isListening ? "Listening" : "Start Listening",
                tint: isListening ? C.listen : C.eve,
                active: isListening
            ) {
                if isListening {
                    store.stopListening()
                    store.voice.stopSpeaking()
                } else {
                    store.startListening()
                }
            }

            if store.fluidListening {
                toolbarButton(
                    icon: store.userMuted ? "mic.slash.fill" : "speaker.wave.2.fill",
                    label: store.userMuted ? "Muted" : "Mute",
                    tint: store.userMuted ? C.danger : C.think,
                    active: store.userMuted
                ) {
                    store.toggleUserMute()
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            toolbarButton(
                icon: isSpeaking ? "pause.fill" : "stop.fill",
                label: isSpeaking ? "Pause Eve" : "Stop Audio",
                tint: isSpeaking ? C.danger : .secondary,
                active: isSpeaking
            ) {
                store.voice.stopSpeaking()
                store.eveStatus = .idle
            }
            .disabled(!isSpeaking)
            .opacity(isSpeaking ? 1 : 0.55)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: store.fluidListening)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: store.userMuted)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: store.eveStatus)
    }

    private func toolbarButton(icon: String, label: String, tint: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(active ? tint : tint.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: active
                                ? [tint.opacity(0.16), Color.white.opacity(0.04)]
                                : [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: active ? tint.opacity(0.10) : Color.black.opacity(0.04), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live thread view (composer integrated, no floating overlay)

struct LiveThreadView: View {
    @ObservedObject var store: LumenStore
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    let onSubmit: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ConversationThread(store: store)
            ComposerBar(
                text: $inputText,
                inputFocused: $inputFocused,
                store: store,
                onSubmit: onSubmit
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.02), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Composer bar (inline, dock at bottom of conversation pane)

struct ComposerBar: View {
    @Binding var text: String
    @FocusState.Binding var inputFocused: Bool
    @ObservedObject var store: LumenStore
    let onSubmit: () -> Void
    @State private var composerExpanded = false

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerMaxHeight: CGFloat {
        composerExpanded ? 180 : 22
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.pendingImages.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(C.eve)
                    Text("\(store.pendingImages.count) image\(store.pendingImages.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { store.clearPendingImages() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if let target = store.replyTarget {
                replyChip(target: target)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if composerExpanded {
                expandedToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: toggleMic) {
                    let active = store.fluidListening || store.eveStatus == .listening
                    Image(systemName: active ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(active ? C.listen : .secondary.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(store.fluidListening ? "Stop listening" : "Start listening")

                ChatComposerField(
                    text: $text,
                    placeholder: "Send a directive\u{2026}  (\u{21E7}\u{21A9} for newline)",
                    minHeight: 22,
                    maxHeight: composerMaxHeight,
                    onSubmit: submitAndCollapse
                )
                .frame(minHeight: 22)

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        composerExpanded.toggle()
                    }
                }) {
                    Image(systemName: composerExpanded ? "chevron.down" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(composerExpanded ? "Collapse" : "Expand tools")

                if store.eveStatus == .speaking {
                    Button(action: { store.voice.stopSpeaking(); store.eveStatus = .idle }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(C.danger, in: Circle())
                    }
                    .buttonStyle(.plain)
                } else if hasContent {
                    Button(action: submitAndCollapse) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(C.eve, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: NSImage.self) {
                    _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                        guard let img = obj as? NSImage,
                              let tiff = img.tiffRepresentation,
                              let bmp  = NSBitmapImageRep(data: tiff),
                              let png  = bmp.representation(using: .png, properties: [:])
                        else { return }
                        let b64 = png.base64EncodedString()
                        DispatchQueue.main.async { store.pendingImages.append(b64) }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { store.attachImage(at: url) }
                    }
                }
            }
            return true
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.88), value: composerExpanded)
    }

    private var expandedToolbar: some View {
        HStack(spacing: 8) {
            Button(action: pickImage) {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)

            Button(action: { insertShortcut("@operations ") }) {
                Text("@ops")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(C.eve.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(C.eve.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: { insertShortcut("@agents ") }) {
                Text("@agents")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(C.eve.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(C.eve.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: { insertShortcut("```\n\n```") }) {
                Text("code")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(C.eve.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(C.eve.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func submitAndCollapse() {
        onSubmit()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
            composerExpanded = false
        }
    }

    private func toggleMic() {
        if store.fluidListening || store.eveStatus == .listening {
            store.stopListening()
            store.voice.stopSpeaking()
        } else {
            store.startListening()
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.image, .jpeg, .png, .gif, .heic]
        panel.message                 = "Attach images for Eve to see (vision via llava)"
        panel.prompt                  = "Attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                store.attachImage(at: url)
            }
        }
    }

    private func insertShortcut(_ insertion: String) {
        if insertion == "```\n\n```" {
            text += text.isEmpty ? insertion : "\n" + insertion
            return
        }
        text += (text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n")) ? insertion : " " + insertion
    }

    @ViewBuilder
    fileprivate func replyChip(target: ChatMessage) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(C.eve).frame(width: 4, height: 4)
            Text(target.content)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: { store.clearReplyTarget() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(C.eve.opacity(0.04), in: Capsule())
    }
}

private struct MentionShortcutChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(C.eve.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(C.eve.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Background

struct BackgroundLayer: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()

            // Tonal gradient on top of the adaptive base
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.03, green: 0.04, blue: 0.10),
                       Color(red: 0.02, green: 0.03, blue: 0.08),
                       Color(red: 0.025, green: 0.025, blue: 0.05)]
                    : [Color(red: 0.99, green: 0.99, blue: 1.0),
                       Color(red: 0.96, green: 0.96, blue: 0.98),
                       Color(red: 0.93, green: 0.94, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Dot matrix
            Canvas { ctx, size in
                let spacing: CGFloat = 48
                ctx.opacity = scheme == .dark ? 0.07 : 0.045
                var x: CGFloat = 0
                while x <= size.width {
                    var y: CGFloat = 0
                    while y <= size.height {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                            with: .color(scheme == .dark ? .white : .black)
                        )
                        y += spacing
                    }
                    x += spacing
                }
            }
            .ignoresSafeArea()

            // Atmospheric Eve glow
            RadialGradient(
                colors: [C.eve.opacity(scheme == .dark ? 0.055 : 0.04), Color.clear],
                center: .center, startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [C.eve.opacity(scheme == .dark ? 0.14 : 0.07), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 760, height: 520)
                .offset(x: -280, y: -180)
                .blur(radius: 70)
        }
    }
}

struct MainStage: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @Binding var showLauncher: Bool
    @Binding var activePanel: MainView.PanelType
    let usesFloatingPanels: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let heroWidth = min(max(width * 0.26, 300), 380)
            let useStackedLayout = width < 1120

            Group {
                if useStackedLayout {
                    VStack(spacing: 20) {
                        HeroDeck(
                            store: store,
                            lmStatus: lmStatus,
                            showLauncher: $showLauncher,
                            activePanel: $activePanel,
                            usesLauncher: usesFloatingPanels
                        )
                        .frame(maxWidth: .infinity)

                        ConversationThread(store: store)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        HeroDeck(
                            store: store,
                            lmStatus: lmStatus,
                            showLauncher: $showLauncher,
                            activePanel: $activePanel,
                            usesLauncher: usesFloatingPanels
                        )
                        .frame(width: heroWidth)

                        WorkspaceCanvas(
                            activePanel: $activePanel,
                            store: store,
                            auth: auth
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Reserve room for the floating InputBar only when it's visible
            // (live thread or map). On Operations/Agents/etc. panels the input
            // bar is hidden, so panels can claim the full window height.
            .padding(.bottom, (activePanel == .none || activePanel == .nexusMap) ? 140 : 24)
        }
    }
}

struct HeroDeck: View {
    @ObservedObject var store: LumenStore
    let lmStatus: MainView.LMStatus
    @Binding var showLauncher: Bool
    @Binding var activePanel: MainView.PanelType
    let usesLauncher: Bool

    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var sync: LumenSync
    @EnvironmentObject var apps: LumenAppRegistry

    private var statusColor: Color { store.eveStatus.color }
    private var messageCount: Int { store.messages.count }
    private func popOut(_ type: MainView.PanelType) {
        openWindow(id: "panel", value: type)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("VOICE RELAY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .tracking(4)
                            Text(store.currentConversationTitle == nil ? "Eve mission console" : "Active conversation")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary.opacity(0.92))
                                .lineLimit(2)
                            Text(statusSummary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .tracking(1.2)
                                .lineLimit(2)
                        }

                        Spacer()

                        StatusChip(label: lmStatus.label, color: lmStatus.isOnline ? C.listen : .secondary.opacity(0.5))
                    }

                    ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [C.eve.opacity(0.18), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.08), lineWidth: 1)

                    VStack(spacing: 12) {
                        EveOrb(status: store.eveStatus, audioLevel: store.audioLevel)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)

                        HStack(spacing: 10) {
                            SignalReadout(title: "STATUS", value: store.eveStatus.label, accent: statusColor)
                            SignalReadout(title: "AUDIO", value: audioLabel, accent: C.listen)
                        }
                    }
                    .padding(18)
                }
                .frame(height: 260)
            }
            .padding(22)
            .background(SurfaceCard(cornerRadius: 30))

            HStack(spacing: 12) {
                MetricTile(label: "messages", value: "\(messageCount)", accent: .primary)
                MetricTile(label: "agents", value: "\(store.agents.count)", accent: C.eve)
                MetricTile(label: "ops", value: "\(store.operations.count)", accent: C.think)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("WORKSPACE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.58))
                    .tracking(3)

                WorkspaceNavButton(label: "Conversation History", detail: "Resume any thread", icon: "bubble.left.and.bubble.right.fill", tint: C.eve, action: {
                    activePanel = .chats
                }, isSelected: {
                    activePanel == .chats
                }, onPopOut: { popOut(.chats) })
                WorkspaceNavButton(label: "Live Conversation", detail: "Primary voice thread", icon: "waveform.circle.fill", tint: .primary, action: {
                    activePanel = .none
                }, isSelected: {
                    activePanel == .none
                })
                WorkspaceNavButton(label: "Agents", detail: "\(store.agents.count) synced", icon: "person.3.fill", tint: C.listen, action: {
                    activePanel = .agents
                }, isSelected: {
                    activePanel == .agents
                }, onPopOut: { popOut(.agents) })
                WorkspaceNavButton(label: "Operations", detail: "\(store.operations.count) active", icon: "bolt.fill", tint: C.think, action: {
                    activePanel = .operations
                }, isSelected: {
                    activePanel == .operations
                }, onPopOut: { popOut(.operations) })
                WorkspaceNavButton(label: "Directives", detail: "\(store.directives.count) loaded", icon: "shield.lefthalf.filled", tint: C.eve, action: {
                    activePanel = .directives
                }, isSelected: {
                    activePanel == .directives
                }, onPopOut: { popOut(.directives) })
                WorkspaceNavButton(label: "Memory Bank", detail: "\(store.memories.count) entries", icon: "brain.head.profile", tint: C.listen, action: {
                    activePanel = .memory
                }, isSelected: {
                    activePanel == .memory
                }, onPopOut: { popOut(.memory) })
                WorkspaceNavButton(label: "Nexus Map", detail: store.nexusMap.nodes.isEmpty ? "Universe view" : "\(store.nexusMap.nodes.count) nodes · \(store.nexusMap.edges.count) edges", icon: "globe", tint: C.eve, action: {
                    activePanel = .nexusMap
                    sync.mapDidOpen()
                    if store.nexusMap.nodes.isEmpty { Task { await store.fetchNexusMap() } }
                }, isSelected: {
                    activePanel == .nexusMap
                }, onPopOut: { popOut(.nexusMap) })
                WorkspaceNavButton(label: "Files", detail: "Local evaluation", icon: "folder.fill", tint: C.eve, action: {
                    activePanel = .files
                }, isSelected: {
                    activePanel == .files
                }, onPopOut: { popOut(.files) })
                WorkspaceNavButton(
                    label: "Code",
                    detail: apps.runningCodeCount > 0
                        ? "\(apps.runningCodeCount) running · \(apps.runningCodeCount == 1 ? "session" : "sessions")"
                        : "Claude Code in any folder",
                    icon: "terminal.fill",
                    tint: apps.runningCodeCount > 0 ? C.listen : C.eve,
                    action: { activePanel = .code },
                    isSelected: { activePanel == .code },
                    onPopOut: { popOut(.code) }
                )
                WorkspaceNavButton(label: "System", detail: "Endpoints and datasets", icon: "cpu.fill", tint: C.listen, action: {
                    activePanel = .system
                }, isSelected: {
                    activePanel == .system
                }, onPopOut: { popOut(.system) })
                WorkspaceNavButton(label: "Settings", detail: "Account and session", icon: "gearshape.fill", tint: C.think, action: {
                    activePanel = .settings
                }, isSelected: {
                    activePanel == .settings
                }, onPopOut: { popOut(.settings) })
            }
            .padding(18)
            .background(SurfaceCard(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 10) {
                Text("CURRENT THREAD")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.58))
                    .tracking(3)

                DetailSection(
                    title: "ACTIVE CONVERSATION",
                    text: store.currentConversationTitle ?? "New live session"
                )

                HStack(spacing: 10) {
                    PanelActionButton(label: "NEW THREAD", color: C.eve, disabled: false) {
                        store.newConversation()
                    }
                    PanelActionButton(label: usesLauncher ? "COMMAND HUB" : "REFRESH DATA", color: C.listen, disabled: false) {
                        if usesLauncher {
                            showLauncher.toggle()
                        } else {
                            Task {
                                await store.fetchDashboard()
                                await store.fetchOperations()
                                await store.fetchConversations()
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(SurfaceCard(cornerRadius: 24))

                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var statusSummary: String {
        switch store.eveStatus {
        case .idle:
            return "Awaiting voice or typed directives"
        case .listening:
            return "Microphone live. Transcript stream is active"
        case .thinking:
            return "Processing response and routing tools"
        case .speaking:
            return "Returning output through the current voice channel"
        }
    }

    private var audioLabel: String {
        let percent = min(max(Int(store.audioLevel * 100), 0), 100)
        return "\(percent)%"
    }
}

private struct WorkspaceCanvas: View {
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager

    var body: some View {
        Group {
            switch activePanel {
            case .none:
                ConversationThread(store: store)
            case .agents:
                WorkspaceSurface(title: "Agents") {
                    AgentPanel(store: store) { activePanel = .none }
                }
            case .operations:
                WorkspaceSurface(title: "Operations") {
                    OpsPanel2(store: store) { activePanel = .none }
                }
            case .directives:
                WorkspaceSurface(title: "Directives") {
                    DirectivesPanel(store: store) { activePanel = .none }
                }
            case .memory:
                WorkspaceSurface(title: "Memory Bank") {
                    MemoryPanel(store: store) { activePanel = .none }
                }
            case .chats:
                WorkspaceSurface(title: "Conversations") {
                    ChatsPanel(store: store) { activePanel = .none }
                }
            case .nexusMap:
                NexusMapView(store: store)
            case .files:
                WorkspaceSurface(title: "Files") {
                    FilesPanel(store: store) { activePanel = .none }
                }
            case .code:
                WorkspaceSurface(title: "Code") {
                    CodePanel(store: store) { activePanel = .none }
                }
            case .system:
                WorkspaceSurface(title: "System") {
                    SystemPanel(store: store) { activePanel = .none }
                }
            case .settings:
                WorkspaceSurface(title: "Settings") {
                    SettingsPanel(store: store, auth: auth) { activePanel = .none }
                }
            }
        }
    }
}

private struct WorkspaceSurface<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SurfaceCard(cornerRadius: 30))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct SurfaceCard: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(C.surface.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(C.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
    }
}

private struct StatusChip: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color, radius: 4)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(C.surfaceHi)
        .overlay(
            Capsule()
                .strokeBorder(C.hairline, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct SignalReadout: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MetricTile: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.92))
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.72))
                .tracking(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkspaceNavButton: View {
    let label: String
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void
    let isSelected: () -> Bool
    var onPopOut: (() -> Void)? = nil  // optional: shows on hover + context menu

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.primary.opacity(0.86))
                    Text(detail)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hovered, let onPopOut {
                    Button(action: onPopOut) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(C.surfaceHi)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in new window")
                    .transition(.opacity)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected() ? tint.opacity(0.12) : C.surfaceHi)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected() ? tint.opacity(0.35) : C.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            if let onPopOut {
                Button("Open in New Window") { onPopOut() }
            }
        }
    }
}

// MARK: - Top HUD helpers

private struct TopStat: View {
    let label: String
    let value: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.92))
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(accent.opacity(0.85))
        }
    }
}

private func timeAgoShort(_ date: Date) -> String {
    let s = -date.timeIntervalSinceNow
    if s < 5 { return "now" }
    if s < 60 { return "\(Int(s))s" }
    if s < 3600 { return "\(Int(s/60))m" }
    if s < 86400 { return "\(Int(s/3600))h" }
    return "\(Int(s/86400))d"
}

// MARK: - Top HUD

struct TopHUD: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @EnvironmentObject var sync: LumenSync

    private var statusColor: Color {
        switch store.eveStatus {
        case .idle:      return .secondary.opacity(0.48)
        case .listening: return C.listen
        case .thinking:  return C.think
        case .speaking:  return C.eve
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.25), lineWidth: 1)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(statusColor.opacity(0.6), lineWidth: 1)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor, radius: 5)
                }
                .animation(.easeInOut(duration: 0.25), value: store.eveStatus)

                VStack(alignment: .leading, spacing: 1) {
                    Text("EVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.6))
                        .tracking(4)
                    Text(store.eveStatus.label)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(statusColor)
                        .tracking(2)
                        .animation(.easeInOut, value: store.eveStatus)
                }
            }

            Spacer()

            Group {
                if store.eveStatus == .listening || store.eveStatus == .speaking {
                    WaveformView(audioLevel: store.audioLevel, color: statusColor)
                        .frame(width: 92, height: 18)
                } else {
                    HStack(spacing: 18) {
                        TopStat(label: "AGENTS", value: "\(store.agents.count)", accent: C.listen)
                        TopStat(label: "OPS",    value: "\(store.operations.count)", accent: C.think)
                        TopStat(label: "MEM",    value: "\(store.memories.count)", accent: C.eve)
                        TopStat(label: "DIR",    value: "\(store.directives.count)", accent: C.eve)
                        if store.nexusMap.nodes.count > 0 {
                            TopStat(label: "MAP", value: "\(store.nexusMap.nodes.count)", accent: .secondary)
                        }
                        if let last = sync.lastDashboardSync {
                            TopStat(label: "SYNCED", value: timeAgoShort(last), accent: .secondary)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.eveStatus)

            Spacer()

            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(lmStatus.isOnline ? C.listen : .secondary.opacity(0.15))
                        .frame(width: 4, height: 4)
                        .shadow(color: lmStatus.isOnline ? C.listen : .clear, radius: 4)
                    Text(lmStatus.label)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(1)
                        .lineLimit(1)
                }

                Button { sync.kickDashboard(); sync.kickConversations(); sync.kickDirectivesAndMemory(); if sync.lastMapSync != nil { sync.kickMap() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Sync now (⌘R)")
                .keyboardShortcut("r", modifiers: [.command])

                TimeDisplay()

                Button { auth.signOut() } label: {
                    Text("LOCK")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(C.hairline), alignment: .bottom)
    }
}

// MARK: - Conversation thread

struct ConversationThread: View {
    @ObservedObject var store: LumenStore
    @Environment(\.openWindow) private var openWindow

    @State private var searchActive: Bool = false
    @State private var searchQuery: String = ""
    @State private var currentMatchIndex: Int = 0
    @FocusState private var searchFocused: Bool

    /// ⌘-click any message to toggle it in the selection. The floating
    /// action bar at the bottom appears whenever this is non-empty and lets
    /// you Read Aloud / Copy / Clear the chosen messages in chronological
    /// order.
    @State private var selectedMessageIds: Set<UUID> = []

    private var selectedMessages: [ChatMessage] {
        // Preserve message order regardless of selection order.
        displayMessages.filter { selectedMessageIds.contains($0.id) }
    }

    private var displayMessages: [ChatMessage] { store.messages }

    /// Indices of messages that match the current query. Computed every render
    /// — cheap at typical thread sizes (≤ a few hundred messages).
    private var searchMatchIndices: [Int] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard searchActive, !q.isEmpty else { return [] }
        return displayMessages.indices.filter { displayMessages[$0].content.lowercased().contains(q) }
    }

    /// id of the currently-highlighted match (if any) — used by the
    /// ScrollViewReader to scroll to it.
    private var currentMatchId: UUID? {
        let m = searchMatchIndices
        guard !m.isEmpty else { return nil }
        let idx = max(0, min(currentMatchIndex, m.count - 1))
        return displayMessages[m[idx]].id
    }

    private var particleIntensity: Double {
        switch store.eveStatus {
        case .speaking:  return 1.0
        case .thinking:  return 0.85
        case .listening: return 0.55
        case .idle:      return 0.32
        }
    }

    /// Quick-view sheet target. When set, an overlay sheet slides in over
    /// the chat (without dismissing it) showing the entity's detail.
    enum QuickView: Identifiable, Hashable {
        case operation(String)
        case agent(String)
        case directive(String)
        var id: String {
            switch self {
            case .operation(let id):  return "op:\(id)"
            case .agent(let id):      return "ag:\(id)"
            case .directive(let id):  return "dir:\(id)"
            }
        }
    }
    @State private var quickView: QuickView? = nil

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            liveThreadHeader
            if searchActive { searchBar }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if displayMessages.isEmpty {
                            // Show the rich Eve briefing dashboard when there's
                            // nothing to display yet — way better than a blank
                            // "standing by" pane.
                            EveBriefingView(store: store)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(Array(displayMessages.enumerated()), id: \.element.id) { idx, msg in
                            let isMatch = searchMatchIndices.contains(idx)
                            let isCurrent = (currentMatchId == msg.id)
                            let isSelected = selectedMessageIds.contains(msg.id)
                            MessageRow(message: msg)
                                .id(msg.id)
                                .padding(.horizontal, (isMatch || isSelected) ? 6 : 0)
                                .padding(.vertical, (isMatch || isSelected) ? 4 : 0)
                                .background(
                                    isCurrent ? C.listen.opacity(0.18) :
                                    isSelected ? C.eve.opacity(0.12) :
                                    (isMatch ? C.listen.opacity(0.08) : Color.clear)
                                )
                                .overlay(alignment: .leading) {
                                    if isSelected {
                                        Rectangle()
                                            .fill(C.eve)
                                            .frame(width: 3)
                                    }
                                }
                                .overlay {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(C.listen.opacity(0.6), lineWidth: 1)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .simultaneousGesture(
                                    // ⌘-click toggles message in selection set
                                    TapGesture().modifiers(.command).onEnded {
                                        toggleSelection(msg.id)
                                    }
                                )
                                .transition(.opacity)
                        }

                        if store.eveStatus == .thinking {
                            ThinkingDots()
                                .transition(.opacity)
                        }

                        if !store.partialTranscript.isEmpty {
                            PartialTranscript(text: store.partialTranscript)
                        }

                        if let err = store.lastError {
                            ErrorRow(text: err)
                        }

                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: displayMessages.count)
                    .animation(.easeInOut(duration: 0.2), value: store.eveStatus)
                }
                .onChange(of: displayMessages.count) { _, _ in
                    if !searchActive {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                    }
                }
                .onChange(of: store.eveStatus) { _, s in
                    if s == .thinking, !searchActive {
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                }
                .onChange(of: store.partialTranscript) { _, _ in
                    if !searchActive { proxy.scrollTo("bottom") }
                }
                .onChange(of: currentMatchIndex) { _, _ in
                    if let id = currentMatchId {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .onChange(of: searchQuery) { _, _ in
                    // Reset cursor to first match whenever the query changes
                    currentMatchIndex = 0
                    if let id = currentMatchId {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    // Always land on the latest message when the chat opens.
                    // Without this the scroll position is undefined and SwiftUI
                    // tends to start at the top, which is wrong for a chat.
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.015), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
            // Selection action bar — appears when ⌘-click selection is non-empty
            if !selectedMessageIds.isEmpty {
                selectionActionBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 88)  // sit above the input bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedMessageIds.count)
            }
        }
        // Quick-view sheet: a dashboard item slides up over the chat without
        // dismissing it, so the Director can dig into something while still
        // seeing Eve's stream.
        .sheet(item: $quickView) { qv in
            CommandCenterQuickView(
                quickView: qv,
                store: store,
                onClose: { quickView = nil },
                onOpenWindow: { type, id in
                    quickView = nil
                    openWindow(id: type, value: id)
                }
            )
            .frame(minWidth: 540, minHeight: 480)
        }
    }

    @ViewBuilder
    private var selectionActionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedMessageIds.count) SELECTED")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                .foregroundColor(C.eve)

            Divider().frame(height: 16)

            Button(action: readSelected) {
                HStack(spacing: 5) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 10, weight: .bold))
                    Text("READ ALOUD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(C.eve)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: copySelected) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc").font(.system(size: 10, weight: .bold))
                    Text("COPY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                }
                .foregroundColor(.primary.opacity(0.85))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: { store.voice.stopSpeaking() }) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
                    Text("STOP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                }
                .foregroundColor(.primary.opacity(0.7))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: clearSelection) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear selection")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .strokeBorder(C.eve.opacity(0.35), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    /// Search bar above the messages, only when active. Shows the query
    /// field, match counter ("3 of 12"), prev/next buttons, and a close (✕).
    /// ESC closes via a hidden button below.
    @ViewBuilder
    private var searchBar: some View {
        let total = searchMatchIndices.count
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(C.listen)
            TextField("Search this thread…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { advanceMatch(by: +1) }

            if !searchQuery.isEmpty {
                Text(total == 0 ? "no matches" : "\(min(currentMatchIndex + 1, total)) of \(total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Button(action: { advanceMatch(by: -1) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 24, height: 22)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(total == 0)

                Button(action: { advanceMatch(by: +1) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(width: 24, height: 22)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(total == 0)
            }

            Button(action: closeSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(
            // ESC closes
            Button("") { closeSearch() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        )
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.15)) { searchActive = true }
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(.easeOut(duration: 0.12)) {
            searchActive = false
            searchQuery = ""
            currentMatchIndex = 0
        }
    }

    private func advanceMatch(by step: Int) {
        let total = searchMatchIndices.count
        guard total > 0 else { return }
        currentMatchIndex = (currentMatchIndex + step + total) % total
    }

    // MARK: - Multi-select

    private func toggleSelection(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if selectedMessageIds.contains(id) {
                selectedMessageIds.remove(id)
            } else {
                selectedMessageIds.insert(id)
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeOut(duration: 0.15)) { selectedMessageIds = [] }
    }

    private func readSelected() {
        let joined = selectedMessages.map(\.content)
            .joined(separator: ".\n\n")  // brief pause between messages
        guard !joined.isEmpty else { return }
        store.voice.speak(joined) {}
    }

    private func copySelected() {
        let joined = selectedMessages.map(\.content)
            .joined(separator: "\n\n")
        guard !joined.isEmpty else { return }
        MessageMeta.copyToClipboard(joined)
    }

    /// Always-visible thread header above the messages — gives the Director
    /// clear "what thread am I in" status + one-click POP OUT / NEW / END+NEW.
    @ViewBuilder
    private var liveThreadHeader: some View {
        let title = threadTitle
        let isLive = store.currentConversationId != nil
        let count = displayMessages.count

        HStack(spacing: 14) {
            Button(action: { store.returnToDashboard() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.eve.opacity(0.85))
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Back to Dashboard")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isLive ? C.eve : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .shadow(color: isLive ? C.eve : .clear, radius: 4)
                    Text(isLive ? "LIVE THREAD" : "FRESH START")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundColor(isLive ? C.eve : .secondary)
                }

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.94))
                    .lineLimit(1)

                Text(threadSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Search this thread — also bound to ⌘F via a hidden button below
            if count > 0 {
                threadHeaderButton(
                    label: "SEARCH",
                    icon: "magnifyingglass",
                    color: C.listen
                ) {
                    if searchActive { closeSearch() } else { openSearch() }
                }
                .help("Search messages in this thread (⌘F)")
            }

            // Pop-out (only when there's something to pop)
            if let cid = store.currentConversationId {
                threadHeaderButton(
                    label: "POP OUT",
                    icon: "rectangle.on.rectangle",
                    color: C.listen
                ) {
                    openWindow(id: "conversation-detail", value: cid)
                }
                .help("Open this thread in its own native window so you can run multiple conversations side by side")
            }

            // End-and-new (only meaningful if there's a live thread)
            if isLive && count > 0 {
                threadHeaderButton(
                    label: "END & NEW",
                    icon: "stop.circle",
                    color: .secondary
                ) {
                    store.newConversation()
                }
                .help("End this conversation and start a fresh thread")
            }

            // New thread always available
            threadHeaderButton(
                label: isLive ? "+" : "NEW",
                icon: "plus.bubble",
                color: C.eve
            ) {
                store.newConversation()
            }
            .help("Start a brand-new conversation")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.025))
        // Hidden button binds ⌘F to search toggle
        .background(
            Button("") {
                if searchActive { closeSearch() } else { openSearch() }
            }
            .keyboardShortcut("f", modifiers: [.command])
            .opacity(0)
        )
    }

    /// Small, dense button for the thread header.
    private func threadHeaderButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
            }
            .foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(0.10))
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var threadTitle: String {
        if let title = store.currentConversationTitle, !title.isEmpty { return title }
        return displayMessages.isEmpty ? "Ready for directives" : "Conversation in progress"
    }

    private var threadSubtitle: String {
        return displayMessages.isEmpty ? "Voice and text routing is online" : "\(displayMessages.count) messages in the active session"
    }
}

struct HistoryBanner: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                    Text("BACK TO LIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(C.eve.opacity(0.7))
            }
            .buttonStyle(.plain)

            Text("·")
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary.opacity(0.58))
                .tracking(1)
                .lineLimit(1)

            Spacer()

            Text("HISTORY")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(C.eve.opacity(0.4))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.eve.opacity(0.3), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(C.eve.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(C.eve.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 32))
                .foregroundStyle(C.eve.opacity(0.7))
            Text("Eve is standing by")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Use the mic for voice or type below.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Eve Briefing
//
// Rich greeting + state summary shown when there's no active conversation.
// Replaces the bland "standing by" empty state. Pulls everything from the
// existing LumenStore — no new endpoint required.

/// Right-rail "command center" widgets shown alongside the active chat.
/// Mirrors the briefing sections but in a compact vertical strip so the
/// Director can keep an eye on system pulse while talking to Eve.
struct CommandCenterRail: View {
    @ObservedObject var store: LumenStore
    let onSelectOperation: (String) -> Void
    let onSelectAgent: (String) -> Void
    let onSelectDirective: (String) -> Void
    @Environment(\.openWindow) private var openWindow

    private var activeOps: [OperationItem] {
        store.operations.filter { $0.status.lowercased() == "active" }
    }
    private var activeAgents: [AgentStatus] {
        store.agents.filter { $0.status.lowercased() == "active" }
    }
    private var topDirectives: [DirectiveItem] {
        store.directives
            .filter { $0.isActive }
            .sorted { $0.priority > $1.priority }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                railHeader

                // ── Eve orb — the centerpiece. Jarvis-style particle reticle
                // with arcs, data ring, audio bloom. Always visible when the
                // command center is open; pulses harder as Eve processes.
                eveCenterpiece

                // Pulse stats
                pulseStrip

                // Briefing delta — what changed since last visit
                if let delta = store.briefingDelta, delta.hasAnyDelta {
                    deltaSection(delta)
                }

                // Active operations — clickable
                if !activeOps.isEmpty {
                    sectionHeader("ACTIVE OPS", count: activeOps.count)
                    VStack(spacing: 5) {
                        ForEach(activeOps.prefix(8)) { op in
                            opRow(op)
                        }
                    }
                }

                // Active agents — clickable
                if !activeAgents.isEmpty {
                    sectionHeader("ACTIVE AGENTS", count: activeAgents.count)
                    VStack(spacing: 5) {
                        ForEach(activeAgents.prefix(8)) { ag in
                            agentRow(ag)
                        }
                    }
                }

                // Directives — clickable
                if !topDirectives.isEmpty {
                    sectionHeader("DIRECTIVES", count: topDirectives.count)
                    VStack(spacing: 5) {
                        ForEach(topDirectives) { d in
                            directiveRow(d)
                        }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 14).padding(.vertical, 16)
        }
        .task {
            await store.fetchBriefingDelta()
        }
    }

    /// Centerpiece — large EveOrb (~200pt) plus status label below. Pulses
    /// dramatically when Eve transitions through listen/think/speak states.
    /// Hover or click the pop-out button to send the orb to its own window.
    private var eveCenterpiece: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                EveOrb(status: store.eveStatus, audioLevel: store.audioLevel)
                    .scaleEffect(0.85)
                    .frame(height: 204)

                // Pop-out button — sends the orb to a dedicated window so the
                // Director can pin it always-on-top or move it to a 2nd monitor
                Button(action: { openWindow(id: "eve-orb") }) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4).padding(.trailing, 8)
                .help("Pop the orb into its own window (⌘⌥E)")
            }

            // Status label + audio meter
            HStack(spacing: 8) {
                Circle()
                    .fill(store.eveStatus.color)
                    .frame(width: 6, height: 6)
                    .shadow(color: store.eveStatus.color, radius: 4)
                Text(store.eveStatus.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(store.eveStatus.color)
                if store.eveStatus == .speaking || store.eveStatus == .listening || store.eveStatus == .thinking {
                    HStack(spacing: 1) {
                        ForEach(0..<6, id: \.self) { i in
                            let bar = max(0.15, min(1.0, CGFloat(store.audioLevel) * CGFloat(i + 1) / 5.0))
                            Capsule()
                                .fill(store.eveStatus.color.opacity(0.7))
                                .frame(width: 2, height: 4 + bar * 12)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Header
    private var railHeader: some View {
        HStack(spacing: 8) {
            Circle().fill(C.eve).frame(width: 7, height: 7)
                .shadow(color: C.eve, radius: 5)
            Text("COMMAND CENTER")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.5)
                .foregroundColor(C.eve)
            Spacer()
            if store.briefingLoading {
                ProgressView().controlSize(.mini).tint(C.eve)
            }
        }
    }

    private var pulseStrip: some View {
        HStack(spacing: 6) {
            pulsePill(label: "OPS",   value: "\(activeOps.count)",       color: C.listen)
            pulsePill(label: "AGT",   value: "\(activeAgents.count)",    color: C.eve)
            pulsePill(label: "DIR",   value: "\(store.directives.filter(\.isActive).count)", color: C.think)
            pulsePill(label: "MEM",   value: "\(store.memories.count)",  color: .secondary)
        }
    }

    private func pulsePill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(color.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Sections

    private func sectionHeader(_ label: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2.5)
                .foregroundColor(.secondary)
            if let c = count {
                Text("\(c)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.7))
            }
            Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.18))
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func deltaSection(_ delta: BriefingDelta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("WHAT CHANGED", count: nil)
            HStack(spacing: 5) {
                if !delta.newOperations.isEmpty {
                    deltaPill("\(delta.newOperations.count)", "OPS",     color: C.eve)
                }
                if !delta.statusChangedOperations.isEmpty {
                    deltaPill("\(delta.statusChangedOperations.count)", "Δ", color: C.think)
                }
                if !delta.newRecords.isEmpty {
                    deltaPill("\(delta.newRecords.count)", "REC",       color: C.listen)
                }
                if delta.findingTotal > 0 {
                    deltaPill("\(delta.findingTotal)",     "FND",       color: .red)
                }
                if !delta.completedResearch.isEmpty {
                    deltaPill("\(delta.completedResearch.count)", "RSCH ✓", color: C.eve)
                }
            }
        }
    }

    private func deltaPill(_ value: String, _ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(color.opacity(0.10))
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
        .clipShape(Capsule())
    }

    // MARK: - Rows (clickable)

    private func opRow(_ op: OperationItem) -> some View {
        Button { onSelectOperation(op.operationId) } label: {
            HStack(spacing: 8) {
                Circle().fill(priorityColor(op.priority)).frame(width: 5, height: 5)
                Text(op.codename.isEmpty ? op.name : op.codename)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(op.priority.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(priorityColor(op.priority))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func agentRow(_ ag: AgentStatus) -> some View {
        Button { onSelectAgent(ag.agentId) } label: {
            HStack(spacing: 8) {
                Circle().fill(C.listen).frame(width: 5, height: 5)
                    .shadow(color: C.listen, radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ag.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.92))
                        .lineLimit(1)
                    Text(ag.role)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if ag.totalFindings > 0 {
                    Text("\(ag.totalFindings)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(C.listen)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(C.listen.opacity(0.13))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func directiveRow(_ d: DirectiveItem) -> some View {
        Button { onSelectDirective(d.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundColor(C.think)
                Text(d.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("P\(d.priority)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func priorityColor(_ p: String) -> Color {
        switch p.lowercased() {
        case "critical": return .red
        case "high":     return .orange
        case "normal":   return C.eve
        case "low":      return .secondary
        default:         return C.listen
        }
    }
}

/// Quick-view sheet that opens over the chat without dismissing it.
/// Lightweight — shows the entity's title, key stats, and a "OPEN IN
/// WINDOW" button to escalate to the full detail window.
struct CommandCenterQuickView: View {
    let quickView: ConversationThread.QuickView
    @ObservedObject var store: LumenStore
    let onClose: () -> Void
    let onOpenWindow: (String, String) -> Void   // (window-id, entity-id)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(headerLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.5)
                    .foregroundColor(C.eve)
                Spacer()
                Button(action: { onOpenWindow(windowId, entityId) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 10, weight: .bold))
                        Text("OPEN AS WINDOW")
                            .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                    }
                    .foregroundColor(C.eve)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(C.eve.opacity(0.12))
                    .overlay(Capsule().strokeBorder(C.eve.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.top, 16)

            Divider()

            ScrollView {
                quickContent
                    .padding(.horizontal, 18).padding(.vertical, 12)
            }
        }
    }

    private var headerLabel: String {
        switch quickView {
        case .operation: return "OPERATION · QUICK VIEW"
        case .agent:     return "AGENT · QUICK VIEW"
        case .directive: return "DIRECTIVE · QUICK VIEW"
        }
    }

    private var entityId: String {
        switch quickView {
        case .operation(let id): return id
        case .agent(let id):     return id
        case .directive(let id): return id
        }
    }

    private var windowId: String {
        switch quickView {
        case .operation: return "operation-detail"
        case .agent:     return "agent-detail"
        case .directive: return "panel"  // directives don't have a dedicated window; route to panel
        }
    }

    @ViewBuilder
    private var quickContent: some View {
        switch quickView {
        case .operation(let id):
            if let op = store.operations.first(where: { $0.operationId == id }) {
                quickOpView(op)
            } else {
                Text("Operation not found").foregroundColor(.secondary)
            }
        case .agent(let id):
            if let ag = store.agents.first(where: { $0.agentId == id }) {
                quickAgentView(ag)
            } else {
                Text("Agent not found").foregroundColor(.secondary)
            }
        case .directive(let id):
            if let d = store.directives.first(where: { $0.id == id }) {
                quickDirectiveView(d)
            } else {
                Text("Directive not found").foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func quickOpView(_ op: OperationItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(op.codename.isEmpty ? op.name : op.codename)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
            if !op.codename.isEmpty {
                Text(op.name).font(.system(size: 13)).foregroundColor(.secondary)
            }
            HStack(spacing: 14) {
                statTile("STATUS",   op.status.uppercased(),   accent: op.status == "active" ? C.listen : .secondary)
                statTile("PRIORITY", op.priority.uppercased(), accent: op.priority == "high" ? .orange : .secondary)
            }
            if !op.description.isEmpty {
                Text("DESCRIPTION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(.secondary)
                Text(op.description)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func quickAgentView(_ ag: AgentStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ag.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
            Text(ag.role).font(.system(size: 13)).foregroundColor(.secondary)
            HStack(spacing: 14) {
                statTile("STATUS",   ag.status.uppercased(),   accent: ag.status == "active" ? C.listen : .secondary)
                statTile("FINDINGS", "\(ag.totalFindings)",    accent: ag.totalFindings > 0 ? C.listen : .secondary)
            }
            Text("LAST ACTION")
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                .foregroundColor(.secondary)
            Text(ag.lastAction)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.85))
        }
    }

    @ViewBuilder
    private func quickDirectiveView(_ d: DirectiveItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(d.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
            HStack(spacing: 14) {
                statTile("TYPE",     d.type.uppercased(),                  accent: C.think)
                statTile("STATE",    d.isActive ? "ACTIVE" : "OFF",        accent: d.isActive ? C.listen : .secondary)
                statTile("PRIORITY", "P\(d.priority)",                     accent: d.priority >= 8 ? C.danger : .secondary)
            }
            Text(d.content)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func statTile(_ label: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(accent.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.20), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EveBriefingView: View {
    @ObservedObject var store: LumenStore
    @State private var now = Date()
    @State private var revealStep: Int = 0   // 0…6 — drives staggered fade-in
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private func revealed(_ step: Int) -> Bool { revealStep >= step }
    private func revealOpacity(_ step: Int) -> Double { revealed(step) ? 1.0 : 0.0 }
    private func revealOffset(_ step: Int) -> CGFloat { revealed(step) ? 0 : 8 }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12:  return "Good morning, sir"
        case 12..<17: return "Good afternoon, sir"
        case 17..<22: return "Good evening, sir"
        default:      return "Standing by, sir"
        }
    }

    private var activeOps: [OperationItem] {
        store.operations.filter { $0.status.lowercased() == "active" }
    }
    private var activeAgents: [AgentStatus] {
        store.agents.filter { $0.status.lowercased() == "active" }
    }
    private var topDirectives: [DirectiveItem] {
        store.directives
            .filter { $0.isActive }
            .sorted { $0.priority > $1.priority }
            .prefix(4)
            .map { $0 }
    }
    private var lastConversation: ConversationSummary? {
        store.conversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .opacity(revealOpacity(1))
                    .offset(y: revealOffset(1))
                statsRow
                    .opacity(revealOpacity(2))
                    .offset(y: revealOffset(2))
                if let delta = store.briefingDelta, delta.hasAnyDelta {
                    deltaSection(delta)
                        .opacity(revealOpacity(3))
                        .offset(y: revealOffset(3))
                }
                if !topDirectives.isEmpty {
                    directivesSection
                        .opacity(revealOpacity(4))
                        .offset(y: revealOffset(4))
                }
                if let conv = lastConversation {
                    lastConvSection(conv)
                        .opacity(revealOpacity(5))
                        .offset(y: revealOffset(5))
                }
                if !activeOps.isEmpty {
                    opsPreview
                        .opacity(revealOpacity(6))
                        .offset(y: revealOffset(6))
                }
                quickPrompts
                    .opacity(revealOpacity(6))
                    .offset(y: revealOffset(6))
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { val in now = val }
        .onAppear {
            runReveal()
            Task { await store.fetchBriefingDelta() }
        }
    }

    /// "What changed since last visit" — counts + key items pulled from the
    /// /api/eve/briefing endpoint. Lights up only when there's actually new
    /// activity to show.
    @ViewBuilder
    private func deltaSection(_ delta: BriefingDelta) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("WHAT CHANGED SINCE LAST VISIT", count: nil)

            // Top counter row
            HStack(spacing: 10) {
                if !delta.newOperations.isEmpty {
                    deltaPill(label: "NEW OPS",     value: "\(delta.newOperations.count)",     color: C.eve)
                }
                if !delta.statusChangedOperations.isEmpty {
                    deltaPill(label: "STATUS Δ",    value: "\(delta.statusChangedOperations.count)", color: C.think)
                }
                if !delta.newRecords.isEmpty {
                    deltaPill(label: "NEW RECORDS", value: "\(delta.newRecords.count)",        color: C.listen)
                }
                if delta.findingTotal > 0 {
                    deltaPill(label: "FINDINGS",    value: "\(delta.findingTotal)",            color: .red)
                }
                if !delta.completedResearch.isEmpty {
                    deltaPill(label: "RESEARCH ✓",  value: "\(delta.completedResearch.count)", color: C.eve)
                }
                Spacer()
            }

            // Inline list — top 3 of each meaningful type
            VStack(alignment: .leading, spacing: 6) {
                ForEach(delta.newOperations.prefix(3)) { op in
                    deltaRow(icon: "plus.circle.fill", color: C.eve,
                             primary: op.label,
                             secondary: "operation · \(op.status.uppercased())")
                }
                ForEach(delta.statusChangedOperations.prefix(3)) { op in
                    deltaRow(icon: "arrow.triangle.2.circlepath.circle.fill", color: C.think,
                             primary: op.label,
                             secondary: "moved to \(op.status.uppercased())")
                }
                ForEach(delta.newRecords.prefix(4)) { rec in
                    deltaRow(icon: "doc.text.fill", color: C.listen,
                             primary: rec.title,
                             secondary: "\(rec.type.uppercased()) · \(rec.operationLabel)")
                }
                ForEach(Array(delta.findingsPerAgent.prefix(4)), id: \.name) { row in
                    deltaRow(icon: "scope", color: .red,
                             primary: "\(row.name) surfaced \(row.count) finding\(row.count == 1 ? "" : "s")",
                             secondary: "")
                }
                ForEach(delta.completedResearch.prefix(2)) { r in
                    deltaRow(icon: "checkmark.seal.fill", color: C.eve,
                             primary: "Research complete \(r.operationLabel.isEmpty ? "" : "· \(r.operationLabel)")",
                             secondary: r.summary)
                }
            }
        }
        .padding(14)
        .background(C.eve.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(C.eve.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func deltaPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08), in: Capsule())
    }

    private func deltaRow(icon: String, color: Color, primary: String, secondary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(2)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Cascade each section in via a 6-tick reveal — ~700ms total. Reads as
    /// "Eve materializing the briefing" rather than a static dump.
    private func runReveal() {
        // If the user already saw it this lifecycle, skip the animation.
        guard revealStep == 0 else { return }
        for step in 1...6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.10) {
                withAnimation(.easeOut(duration: 0.32)) {
                    revealStep = step
                }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(C.eve)
                    .frame(width: 9, height: 9)
                    .shadow(color: C.eve, radius: 6)
                Text("EVE · NEXUS BRIEFING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(3)
                    .foregroundColor(C.eve)
                Spacer()
                Text(now.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(greeting)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.primary)
            Text("Here's where everything stands. Tap into anything, or open the input below to talk.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            briefStat(label: "OPERATIONS", value: "\(activeOps.count)", total: store.operations.count, color: C.listen)
            briefStat(label: "AGENTS",     value: "\(activeAgents.count)", total: store.agents.count, color: C.eve)
            briefStat(label: "DIRECTIVES", value: "\(store.directives.filter(\.isActive).count)", total: store.directives.count, color: C.think)
            briefStat(label: "MEMORIES",   value: "\(store.memories.count)", total: store.memories.count, color: .secondary)
            briefStat(label: "THREADS",    value: "\(store.conversations.count)", total: store.conversations.count, color: C.eve.opacity(0.7))
        }
    }

    private var directivesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DIRECTIVES NEEDING ATTENTION", count: topDirectives.count)
            ForEach(topDirectives) { d in
                HStack(alignment: .top, spacing: 10) {
                    Text("→")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(C.think)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(d.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.92))
                            Text(d.type.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if !d.content.isEmpty {
                            Text(d.content)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func lastConvSection(_ conv: ConversationSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("LAST CONVERSATION", count: nil)
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(C.eve).frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(conv.title.isEmpty ? "Untitled" : conv.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("\(conv.messageCount) MSG\(conv.messageCount == 1 ? "" : "S")")
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        Text(conv.updatedAt.lumenRelative)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if !conv.preview.isEmpty {
                        Text(conv.preview)
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.75))
                            .lineLimit(3)
                    }
                    HStack(spacing: 8) {
                        Button(action: {
                            Task { await store.loadConversation(id: conv.id, title: conv.title) }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 11))
                                Text("CONTINUE THIS THREAD")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(C.eve)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Button(action: { store.newConversation() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 11))
                                Text("START FRESH")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                            }
                            .foregroundColor(.primary.opacity(0.85))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.15))
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(C.eve.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(C.eve.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var opsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ACTIVE OPERATIONS", count: activeOps.count)
            VStack(spacing: 6) {
                ForEach(activeOps.prefix(4)) { op in
                    HStack(spacing: 10) {
                        Circle().fill(priorityColor(op.priority)).frame(width: 6, height: 6)
                        Text(op.codename.isEmpty ? op.name : op.codename)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.9))
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(op.name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(op.priority.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                            .foregroundColor(priorityColor(op.priority))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if activeOps.count > 4 {
                    Text("+ \(activeOps.count - 4) more — open OPERATIONS panel")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private var quickPrompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("QUICK PROMPTS", count: nil)
            FlowLayoutMV(spacing: 6) {
                ForEach([
                    "Brief me on current operations",
                    "What did the agents find recently",
                    "What needs my attention",
                    "Summarize my open directives",
                    "What's pending in the memory bank"
                ], id: \.self) { prompt in
                    Button(action: {
                        // Send straight to Eve — fresh thread, no prefill step
                        Task { await store.send(prompt) }
                    }) {
                        Text(prompt)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.85))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: helpers

    private func sectionHeader(_ label: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.5)
                .foregroundColor(.secondary)
            if let c = count {
                Text("\(c)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.7))
            }
            Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.18))
        }
    }

    private func briefStat(label: String, value: String, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                if total > 0, "\(total)" != value {
                    Text("/ \(total)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(color.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func priorityColor(_ p: String) -> Color {
        switch p.lowercased() {
        case "critical": return .red
        case "high":     return .orange
        case "normal":   return C.eve
        case "low":      return .secondary
        default:         return C.listen
        }
    }
}

// Local flow layout used by the briefing's quick-prompts row.
private struct FlowLayoutMV: Layout {
    let spacing: CGFloat
    init(spacing: CGFloat = 4) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Message rows

struct MessageRow: View {
    let message: ChatMessage
    private var isEve: Bool { message.role == .assistant }

    var body: some View {
        Group {
            if isEve { EveMessage(message: message) }
            else      { UserMessage(message: message) }
        }
    }
}

/// Shared helpers for the brain badge + per-message hover actions.
private enum MessageMeta {
    static func brainStyle(_ b: String) -> (label: String, color: Color) {
        switch b {
        case "grok":    return ("GROK",    C.eve)
        case "local":   return ("LOCAL",   C.listen)
        case "claude":  return ("CLAUDE",  C.think)
        case "vision":  return ("VISION",  C.listen)
        case "offline": return ("OFFLINE", .secondary)
        default:        return (b.uppercased(), .secondary)
        }
    }

    static func clockTime(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }

    static func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

private struct BrainPill: View {
    let brain: String
    var body: some View {
        let (label, color) = MessageMeta.brainStyle(brain)
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
            .foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.13))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
            .clipShape(Capsule())
    }
}

private struct HoverActions: View {
    let timestamp: Date
    let copyText: String
    let alignTrailing: Bool
    /// Optional speak handler — when present a 🔊 button is shown.
    var onSpeak: (() -> Void)? = nil

    @State private var copied: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(MessageMeta.clockTime(timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            if let onSpeak {
                Button(action: onSpeak) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Read aloud")
            }
            Button(action: doCopy) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(copied ? C.listen : .secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Copy message")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.12), in: Capsule())
        .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
        .transition(.opacity)
    }

    private func doCopy() {
        MessageMeta.copyToClipboard(copyText)
        withAnimation(.easeInOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.18)) { copied = false }
        }
    }
}

struct EveMessage: View {
    let message: ChatMessage
    @EnvironmentObject var store: LumenStore
    @State private var hovering: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(C.eve.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.eve)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Eve")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                    if let b = message.brain {
                        BrainPill(brain: b)
                    }
                    if !message.toolCalls.isEmpty {
                        Text("\(message.toolCalls.count) ACTION\(message.toolCalls.count == 1 ? "" : "S")")
                            .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                            .foregroundColor(C.listen)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(C.listen.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                    if hovering {
                        HoverActions(
                            timestamp: message.timestamp,
                            copyText: message.content,
                            alignTrailing: true,
                            onSpeak: { store.voice.speak(message.content) {} }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if !message.toolCalls.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(message.toolCalls) { tc in
                                ToolCallCardView(summary: tc)
                            }
                        }
                    }

                    ForEach(Array(MentionRenderer.segmented(message.content).enumerated()), id: \.offset) { _, seg in
                        switch seg {
                        case .prose(let text):
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(MentionRenderer.attributedRich(text))
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary.opacity(0.92))
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .environment(\.openURL, OpenURLAction { url in
                                        if MentionRenderer.handle(url: url) { return .handled }
                                        return .systemAction
                                    })
                            }
                        case .code(let lang, let body):
                            CodeBlockView(language: lang, code: body)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button {
                store.setReplyTarget(message)
            } label: {
                Label("Reply to This", systemImage: "arrowshape.turn.up.left.fill")
            }
            Divider()
            Button {
                store.voice.speak(message.content) {}
            } label: {
                Label("Read Aloud", systemImage: "speaker.wave.2.fill")
            }
            Button {
                store.voice.stopSpeaking()
            } label: {
                Label("Stop Speaking", systemImage: "stop.fill")
            }
            Divider()
            Button {
                MessageMeta.copyToClipboard(message.content)
            } label: {
                Label("Copy Message", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Mention renderer

/// Parses Eve's `@[label](type:id)` tokens out of plain text and renders
/// them as colored inline links. Tap routes via `nexus://` URL scheme into
/// a Notification that MainView listens for to navigate the active panel.
enum MentionRenderer {
    static func attributed(_ raw: String) -> AttributedString {
        var out = AttributedString()
        // Pattern: @[label](type:id)
        // type: alphanumeric/underscore — currently operation, agent, record, conversation, topic, memory, directive
        let pattern = #"\@\[([^\]]+)\]\(([a-z_]+):([a-zA-Z0-9\-]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(raw)
        }

        let nsRaw = raw as NSString
        var cursor = 0
        regex.enumerateMatches(in: raw, range: NSRange(location: 0, length: nsRaw.length)) { match, _, _ in
            guard let m = match, m.numberOfRanges == 4 else { return }
            // Plain text before this match
            if m.range.location > cursor {
                let plain = nsRaw.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                out.append(AttributedString(plain))
            }
            let label = nsRaw.substring(with: m.range(at: 1))
            let type  = nsRaw.substring(with: m.range(at: 2))
            let id    = nsRaw.substring(with: m.range(at: 3))

            var chip = AttributedString("@\(label)")
            chip.foregroundColor = MentionRenderer.color(for: type)
            chip.underlineStyle = .single
            // Encode type+id into a custom URL so onOpenURL can route it
            chip.link = URL(string: "nexus://mention/\(type)/\(id)")
            out.append(chip)

            cursor = m.range.location + m.range.length
        }
        if cursor < nsRaw.length {
            let tail = nsRaw.substring(from: cursor)
            out.append(AttributedString(tail))
        }
        return out
    }

    /// Returns true if the URL is a nexus:// mention and the notification was posted.
    static func handle(url: URL) -> Bool {
        guard url.scheme == "nexus", url.host == "mention" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return false }
        let type = parts[0]
        let id   = parts[1]
        NotificationCenter.default.post(
            name: .lumenMentionTap,
            object: nil,
            userInfo: ["type": type, "id": id]
        )
        return true
    }

    private static func color(for type: String) -> Color {
        publicColor(for: type)
    }

    /// Same mapping as the inline chip color but exposed for other UI
    /// (mention autocomplete popup, etc.) so they share a single source.
    static func publicColor(for type: String) -> Color {
        switch type {
        case "operation":        return C.think
        case "agent":            return C.listen
        case "record":           return Color(red: 1.0, green: 0.55, blue: 0.4)  // orange
        case "conversation":     return C.eve
        case "topic":            return Color(red: 0.55, green: 0.85, blue: 1.0) // sky
        case "memory":           return C.listen
        case "directive":        return C.eve
        default:                 return .secondary.opacity(0.7)
        }
    }

    /// Rich rendering: parses inline markdown (**bold**, *italic*, `code`,
    /// [text](url), bullet lists) AND nexus mention chips. Used by
    /// EveMessage etc. so Eve's replies don't show literal asterisks.
    static func attributedRich(_ raw: String) -> AttributedString {
        // 1. Rewrite our @[label](type:id) tokens into markdown links pointing
        //    at our custom URL scheme so the markdown parser turns them into
        //    addressable links we can recolor afterward.
        let pattern = #"\@\[([^\]]+)\]\(([a-z_]+):([a-zA-Z0-9\-]+)\)"#
        let nsRaw = raw as NSString
        var transformed = ""
        var cursor = 0

        if let re = try? NSRegularExpression(pattern: pattern) {
            re.enumerateMatches(in: raw, range: NSRange(location: 0, length: nsRaw.length)) { m, _, _ in
                guard let m, m.numberOfRanges == 4 else { return }
                if m.range.location > cursor {
                    transformed += nsRaw.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                }
                let label = nsRaw.substring(with: m.range(at: 1))
                let type  = nsRaw.substring(with: m.range(at: 2))
                let id    = nsRaw.substring(with: m.range(at: 3))
                transformed += "[@\(label)](nexus://mention/\(type)/\(id))"
                cursor = m.range.location + m.range.length
            }
        }
        if cursor < nsRaw.length { transformed += nsRaw.substring(from: cursor) }
        if transformed.isEmpty { transformed = raw }

        // 2. Parse markdown. inlineOnlyPreservingWhitespace keeps newlines intact
        //    so multi-line replies render correctly without losing structure.
        var attr: AttributedString
        do {
            attr = try AttributedString(
                markdown: transformed,
                options: .init(allowsExtendedAttributes: true,
                               interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            attr = AttributedString(transformed)
        }

        // 3. Recolor any mention links by entity type.
        for run in attr.runs {
            if let url = run.link, url.scheme == "nexus", url.host == "mention" {
                let parts = url.pathComponents.filter { $0 != "/" }
                let type = parts.first ?? ""
                attr[run.range].foregroundColor = publicColor(for: type)
                attr[run.range].underlineStyle = .single
            }
        }

        return attr
    }

    /// Strip fenced code blocks out of `raw` and return ordered segments.
    /// Each segment is either plain prose (rendered with attributedRich)
    /// or a code block (rendered as a styled monospace box).
    enum Segment {
        case prose(String)
        case code(language: String, body: String)
    }

    static func segmented(_ raw: String) -> [Segment] {
        // Walk through the string, splitting on ``` fences.
        var segments: [Segment] = []
        var i = raw.startIndex
        while i < raw.endIndex {
            // Look for the next ``` fence
            if let fenceStart = raw.range(of: "```", range: i..<raw.endIndex) {
                // Emit prose before the fence
                if fenceStart.lowerBound > i {
                    segments.append(.prose(String(raw[i..<fenceStart.lowerBound])))
                }
                // Find closing fence
                let bodyStart = fenceStart.upperBound
                if let fenceEnd = raw.range(of: "```", range: bodyStart..<raw.endIndex) {
                    let block = String(raw[bodyStart..<fenceEnd.lowerBound])
                    // First line after ``` may be a language tag
                    var lang = ""
                    var body = block
                    if let nl = block.firstIndex(of: "\n") {
                        let firstLine = String(block[..<nl]).trimmingCharacters(in: .whitespaces)
                        if !firstLine.isEmpty && firstLine.count <= 24 && firstLine.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "+" || $0 == "_" }) {
                            lang = firstLine
                            body = String(block[block.index(after: nl)...])
                        }
                    }
                    segments.append(.code(language: lang, body: body))
                    i = fenceEnd.upperBound
                } else {
                    // Unterminated fence — treat the rest as prose
                    segments.append(.prose(String(raw[fenceStart.lowerBound..<raw.endIndex])))
                    i = raw.endIndex
                }
            } else {
                segments.append(.prose(String(raw[i..<raw.endIndex])))
                i = raw.endIndex
            }
        }
        return segments
    }
}

/// Visible chip rendered above Eve's prose when she fires a tool. Makes
/// her actions concrete instead of invisible behind a natural-language
/// summary. One card per tool call, in invocation order.
private struct ToolCallCardView: View {
    let summary: ToolCallSummary

    private var accent: Color {
        if !summary.success { return C.danger }
        switch summary.name {
        case _ where summary.name.hasPrefix("arena_task"):    return C.listen
        case _ where summary.name.hasPrefix("arena_payment"): return C.danger
        case _ where summary.name.hasPrefix("arena_sync"):    return C.eve
        case _ where summary.name.hasPrefix("arena_recent"):  return .secondary
        default:                                              return C.eve
        }
    }

    private var icon: String {
        if !summary.success { return "exclamationmark.triangle.fill" }
        switch summary.name {
        case "arena_task_create": return "checkmark.seal.fill"
        case "arena_task_update": return "pencil.circle.fill"
        case "arena_payment_route": return "dollarsign.circle.fill"
        case "arena_sync_push":   return "arrow.up.to.line.circle.fill"
        case "arena_recent":      return "list.bullet.rectangle.portrait.fill"
        default:                  return "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(summary.humanLabel.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                        .foregroundColor(accent)
                    if !summary.success {
                        Text("FAILED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                            .foregroundColor(C.danger)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(C.danger.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(summary.primary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                if !summary.detail.isEmpty {
                    Text(summary.detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Styled fenced-code block — monospace body + copy button.
private struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: copy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .bold))
                        Text(copied ? "COPIED" : "COPY")
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                    }
                    .foregroundColor(copied ? C.listen : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.10))

            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(Color.secondary.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)
        withAnimation(.easeInOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.18)) { copied = false }
        }
    }
}

struct UserMessage: View {
    let message: ChatMessage
    @EnvironmentObject var store: LumenStore
    @State private var hovering: Bool = false
    @State private var isEditing: Bool = false
    @State private var editText: String = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if hovering && !isEditing {
                HStack(spacing: 6) {
                    Spacer()
                    Text(MessageMeta.clockTime(message.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button(action: { store.voice.speak(message.content) {} }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Read aloud")
                    Button(action: startEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Edit this prompt and regenerate Eve's reply")
                    Button(action: { MessageMeta.copyToClipboard(message.content) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
                .padding(.trailing, 4)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.12), in: Capsule())
                .transition(.opacity)
            }
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 110)
                if isEditing {
                    HStack(alignment: .top, spacing: 8) {
                        TextField("", text: $editText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .lineLimit(1...6)
                            .onSubmit(saveEdit)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(C.eve.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(C.eve.opacity(0.3), lineWidth: 1)
                            )
                            .frame(minWidth: 220)
                        VStack(spacing: 6) {
                            Button(action: saveEdit) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(C.eve)
                            }
                            .buttonStyle(.plain)
                            .help("Re-send with edits")
                            Button(action: cancelEdit) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel")
                        }
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary.opacity(0.94))
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(C.eve.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contextMenu {
                            Button {
                                store.voice.speak(message.content) {}
                            } label: {
                                Label("Read Aloud", systemImage: "speaker.wave.2.fill")
                            }
                            Button {
                                store.voice.stopSpeaking()
                            } label: {
                                Label("Stop Speaking", systemImage: "stop.fill")
                            }
                            Divider()
                            Button { startEdit() } label: {
                                Label("Edit & Regenerate", systemImage: "pencil")
                            }
                            Button {
                                MessageMeta.copyToClipboard(message.content)
                            } label: {
                                Label("Copy Message", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func startEdit() {
        editText = message.content
        withAnimation(.easeOut(duration: 0.12)) { isEditing = true }
    }

    private func cancelEdit() {
        withAnimation(.easeOut(duration: 0.12)) { isEditing = false }
        editText = ""
    }

    private func saveEdit() {
        let cleaned = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != message.content else {
            cancelEdit(); return
        }
        let id = message.id
        isEditing = false
        Task { await store.regenerate(fromUserMessageId: id, newText: cleaned) }
    }
}

struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.38, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LinearGradient(colors: [C.eve.opacity(0.35), C.eve.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                .frame(width: 2).cornerRadius(1).frame(height: 28)

            HStack(spacing: 7) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i == phase % 3 ? C.eve : C.eve.opacity(0.2))
                        .frame(width: 5, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: phase)
                }
            }
            .padding(.top, 10)
            Spacer()
        }
        .onReceive(timer) { _ in phase += 1 }
    }
}

struct PartialTranscript: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            C.listen.opacity(0.5).frame(width: 2).cornerRadius(1).frame(height: 24)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(C.listen.opacity(0.65))
                .italic()
            Spacer()
        }
    }
}

struct ErrorRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            C.danger.opacity(0.5).frame(width: 2).cornerRadius(1).frame(height: 24)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(C.danger.opacity(0.8))
                .tracking(0.5)
            Spacer()
        }
    }
}

// MARK: - Cosmic particle field
//
// SwiftUI Canvas + TimelineView. Particles drift slowly when Eve is idle,
// quicken and brighten when she's listening / thinking / speaking. Cheap —
// pseudo-random per-particle parameters, no allocation per frame.

struct CosmicParticles: View {
    /// 0…1. 0 = barely visible drift, 1 = swirling, bright. Animates smoothly.
    var intensity: Double = 0.35
    var tint: Color = C.eve

    private let seed: Double

    init(intensity: Double = 0.35, tint: Color = C.eve) {
        self.intensity = intensity
        self.tint = tint
        self.seed = Double.random(in: 0...1000)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let intensity = max(0, min(1, intensity))
                let count = 60 + Int(intensity * 80)              // 60…140 motes
                let speed = 0.4 + intensity * 1.6
                let baseAlpha = 0.05 + 0.18 * intensity

                // Drift particles
                for i in 0..<count {
                    let phase = Double(i) * 1.234 + seed
                    let baseX = sin(phase * 0.71) * 0.5 + 0.5         // 0…1
                    let baseY = cos(phase * 0.93) * 0.5 + 0.5
                    let driftX = sin(t * speed * 0.30 + phase) * 0.10
                    let driftY = cos(t * speed * 0.40 + phase * 1.7) * 0.08
                    let x = (baseX + driftX) * size.width
                    let y = (baseY + driftY) * size.height
                    let twink = sin(t * 1.8 + phase * 1.3) * 0.5 + 0.5
                    let r = 0.6 + 1.4 * twink
                    let alpha = baseAlpha + 0.14 * intensity * twink
                    let path = Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                       width: r * 2, height: r * 2))
                    ctx.fill(path, with: .color(tint.opacity(alpha)))
                }

                // Brighter "stars" with bigger twinkle
                let starCount = 12 + Int(intensity * 10)
                for i in 0..<starCount {
                    let phase = Double(i) * 7.13 + seed * 0.5
                    let baseX = sin(phase * 0.41) * 0.5 + 0.5
                    let baseY = cos(phase * 0.79) * 0.5 + 0.5
                    let twink = max(0, sin(t * 1.2 + phase))
                    let x = baseX * size.width
                    let y = baseY * size.height
                    let r = 1.0 + 1.6 * twink * intensity
                    let alpha = 0.10 + 0.40 * twink * intensity
                    let path = Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                       width: r * 2, height: r * 2))
                    ctx.fill(path, with: .color(.white.opacity(alpha * 0.5)))
                }

                // Speaking-state: a few slow comet streaks across the canvas
                if intensity > 0.7 {
                    let streaks = 3
                    for i in 0..<streaks {
                        let phase = Double(i) * 23.7 + seed
                        let cycle = (t * 0.18 + phase).truncatingRemainder(dividingBy: 4.0) / 4.0  // 0…1
                        let y = (sin(phase * 1.3) * 0.5 + 0.5) * size.height
                        let x = cycle * (size.width + 200) - 100
                        let len: CGFloat = 60 + 20 * sin(t * 2 + phase)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y))
                        p.addLine(to: CGPoint(x: x - len, y: y - len * 0.2))
                        ctx.stroke(p, with: .color(tint.opacity(0.25 * intensity)),
                                   lineWidth: 0.8)
                    }
                }
            }
            .blur(radius: intensity > 0.6 ? 0.4 : 0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Mention autocomplete (nexus-web parity)

struct MentionCandidate: Identifiable, Hashable {
    let id: String          // "type:entityId" — stable for ForEach
    let type: String        // operation | agent | record | conversation | directive | memory
    let entityId: String
    let label: String
    let subtitle: String
}

enum MentionCatalog {
    /// Build a flat list of taggable entities from the store, filtered by query.
    static func candidates(store: LumenStore, query: String, limit: Int = 8) -> [MentionCandidate] {
        var out: [MentionCandidate] = []

        for op in store.operations {
            let label = op.codename.isEmpty ? op.name : op.codename
            out.append(MentionCandidate(id: "operation:\(op.operationId)",
                                         type: "operation",
                                         entityId: op.operationId,
                                         label: label,
                                         subtitle: op.codename.isEmpty ? "" : op.name))
        }
        for ag in store.agents {
            out.append(MentionCandidate(id: "agent:\(ag.agentId)",
                                         type: "agent",
                                         entityId: ag.agentId,
                                         label: ag.name,
                                         subtitle: ag.role))
        }
        for d in store.directives {
            out.append(MentionCandidate(id: "directive:\(d.id)",
                                         type: "directive",
                                         entityId: d.id,
                                         label: d.title.isEmpty ? "Untitled directive" : d.title,
                                         subtitle: d.type.uppercased()))
        }
        for m in store.memories {
            let preview = String(m.content.prefix(48))
            out.append(MentionCandidate(id: "memory:\(m.id)",
                                         type: "memory",
                                         entityId: m.id,
                                         label: preview.isEmpty ? "Empty memory" : preview,
                                         subtitle: m.type.uppercased()))
        }
        for c in store.conversations.prefix(40) {
            out.append(MentionCandidate(id: "conversation:\(c.id)",
                                         type: "conversation",
                                         entityId: c.id,
                                         label: c.title.isEmpty ? "Untitled thread" : c.title,
                                         subtitle: c.preview.isEmpty ? c.source.uppercased()
                                                                     : String(c.preview.prefix(60))))
        }

        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? out : out.filter {
            $0.label.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
        return Array(filtered.prefix(limit))
    }

    /// Locate trailing `@<query>` token in the input. Returns the @ position
    /// and the query text after it, or nil if not in mention-mode.
    /// Triggers on @ at start-of-string OR preceded by whitespace.
    static func detectQuery(in text: String) -> (atIndex: String.Index, query: String)? {
        // Scan from end backwards looking for @
        guard let atIdx = text.range(of: "@", options: .backwards)?.lowerBound else { return nil }
        // Bail if the character before @ is alphanumeric (likely an email/something else)
        if atIdx > text.startIndex {
            let prev = text[text.index(before: atIdx)]
            if prev.isLetter || prev.isNumber { return nil }
        }
        let after = text[text.index(after: atIdx)...]
        // Stop at any whitespace/newline within the query
        if after.contains(where: { $0.isWhitespace || $0.isNewline }) { return nil }
        // Don't fire for already-formed @[label](...) — those start with [
        if after.hasPrefix("[") { return nil }
        return (atIdx, String(after))
    }

    /// Replace the trailing `@query` token with a fully-formed mention chip.
    static func insert(_ candidate: MentionCandidate, into text: String) -> String {
        guard let (atIdx, _) = detectQuery(in: text) else { return text }
        let prefix = text[..<atIdx]
        // Render as @[label](type:id) — exactly the format Eve uses already.
        let chip = "@[\(candidate.label)](\(candidate.type):\(candidate.entityId)) "
        return String(prefix) + chip
    }
}

private struct MentionAutocompletePopup: View {
    let candidates: [MentionCandidate]
    let onSelect: (MentionCandidate) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "at").font(.system(size: 9, weight: .bold))
                    .foregroundColor(C.eve)
                Text("MENTION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Esc to dismiss")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            if candidates.isEmpty {
                Text("No matches")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            } else {
                ForEach(candidates) { c in
                    Button(action: { onSelect(c) }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(MentionRenderer.publicColor(for: c.type))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.9))
                                    .lineLimit(1)
                                if !c.subtitle.isEmpty {
                                    Text(c.subtitle)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(c.type.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.clear)
                }
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(C.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

// MARK: - Slash commands

struct SlashCommand: Identifiable, Hashable {
    let id: String           // "/new"
    let label: String
    let detail: String
}

enum SlashCommandRegistry {
    /// Built-in actions (run on selection).
    static let actions: [SlashCommand] = [
        SlashCommand(id: "/new",    label: "/new",    detail: "End this thread and start a new one"),
        SlashCommand(id: "/end",    label: "/end",    detail: "Same as /new — explicit ending of the current thread"),
        SlashCommand(id: "/local",  label: "/local",  detail: "Switch to local Ollama brain"),
        SlashCommand(id: "/cloud",  label: "/cloud",  detail: "Switch back to nexus-web Grok brain"),
        SlashCommand(id: "/pop",    label: "/pop",    detail: "Pop the active thread out into its own window"),
        SlashCommand(id: "/clear",  label: "/clear",  detail: "Clear visible messages without ending the thread"),
        SlashCommand(id: "/help",   label: "/help",   detail: "Print available slash commands"),
    ]

    static var all: [SlashCommand] {
        actions + TemplateLibrary.asSlashCommands
    }

    static func filter(_ q: String) -> [SlashCommand] {
        let qq = q.lowercased()
        guard !qq.isEmpty, qq.first == "/" else { return [] }
        if qq == "/" { return all }
        return all.filter { $0.id.hasPrefix(qq) }
    }
}

/// Saved prompt templates — pick one with a slash command, body gets
/// inserted into the input ready to be sent (or further edited).
enum TemplateLibrary {
    struct Template {
        let id: String        // matches SlashCommand id, e.g. "/standup"
        let detail: String    // shown in popup
        let body: String      // text inserted into input
    }

    static let templates: [Template] = [
        Template(
            id: "/standup",
            detail: "Template: morning standup brief",
            body: "Give me a brief morning standup: yesterday's wins, today's priorities, blockers, and anything I'm forgetting."
        ),
        Template(
            id: "/review",
            detail: "Template: weekly review",
            body: "Help me run a weekly review. Pull all operations updated this week, agent findings, completed research, and surface what I might have missed."
        ),
        Template(
            id: "/dump",
            detail: "Template: brain-dump capture",
            body: "I'm about to brain-dump. Capture what I say as memories or operations as appropriate. Ask only if something is genuinely ambiguous."
        ),
        Template(
            id: "/morning",
            detail: "Template: morning brief",
            body: "Morning brief: what's overdue, what's important today, status pulse on active operations, anything that needs my attention."
        ),
        Template(
            id: "/eod",
            detail: "Template: end-of-day wrap",
            body: "End-of-day wrap: summarize what I worked on today across operations and conversations, what's still open, and one thing I should sleep on."
        ),
    ]

    static var asSlashCommands: [SlashCommand] {
        templates.map { SlashCommand(id: $0.id, label: $0.id, detail: $0.detail) }
    }

    static func body(for id: String) -> String? {
        templates.first(where: { $0.id == id })?.body
    }
}

private struct SlashCommandPopup: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command").font(.system(size: 9, weight: .bold))
                    .foregroundColor(C.think)
                Text("COMMAND")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Enter to run")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            ForEach(commands) { c in
                Button(action: { onSelect(c) }) {
                    HStack(spacing: 10) {
                        Text(c.label)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(C.think)
                            .frame(minWidth: 64, alignment: .leading)
                        Text(c.detail)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.8))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(C.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

// MARK: - Input bar

struct InputBar: View {
    @Binding var text: String
    @FocusState.Binding var inputFocused: Bool
    @Binding var showLauncher: Bool
    let usesLauncher: Bool
    @ObservedObject var store: LumenStore
    let onSubmit: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var mentionQuery: String? = nil
    @State private var slashQuery: String? = nil

    private var mentionCandidates: [MentionCandidate] {
        guard let q = mentionQuery else { return [] }
        return MentionCatalog.candidates(store: store, query: q)
    }

    private var slashCommands: [SlashCommand] {
        guard let q = slashQuery else { return [] }
        return SlashCommandRegistry.filter(q)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Slash command popup — sits above the input, only when typing /…
            if let _ = slashQuery, !slashCommands.isEmpty {
                SlashCommandPopup(commands: slashCommands, onSelect: runSlashCommand)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 110)  // align under the text field
            }
            // Mention autocomplete popup
            else if mentionQuery != nil {
                MentionAutocompletePopup(
                    candidates: mentionCandidates,
                    onSelect: insertMention,
                    onDismiss: { mentionQuery = nil }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 110)
            }

            // Attached-image strip — shown above the input when vision pending
            if !store.pendingImages.isEmpty {
                HStack(spacing: 8) {
                    Text("VISION · \(store.pendingImages.count) image\(store.pendingImages.count == 1 ? "" : "s")")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(C.think)
                        .tracking(2)
                    Spacer()
                    Button(action: { store.clearPendingImages() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            Text("CLEAR").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(C.think.opacity(0.08))
                .overlay(Capsule().strokeBorder(C.think.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            inputRow
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: store.pendingImages.count)
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Button(action: toggleMic) {
                let active = store.fluidListening || store.eveStatus == .listening
                ZStack {
                    Circle()
                        .fill(active ? C.listen.opacity(0.18) : C.surfaceHi)
                    Circle()
                        .stroke(active ? C.listen.opacity(0.5) : C.hairline, lineWidth: 1)
                    Image(systemName: active ? "mic.fill" : "mic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(active ? C.listen : .secondary.opacity(0.4))
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .help(store.fluidListening ? "Voice mode is on — tap to stop" : "Tap to start voice mode")

            // Mute toggle — only shown while a voice session is active.
            // Lets Director silence themselves so Eve can finish uninterrupted
            // without ending the session entirely.
            if store.fluidListening {
                Button(action: { store.toggleUserMute() }) {
                    let muted = store.userMuted
                    ZStack {
                        Circle().fill(muted ? C.danger.opacity(0.18) : C.surfaceHi)
                        Circle().stroke(muted ? C.danger.opacity(0.5) : C.hairline, lineWidth: 1)
                        Image(systemName: muted ? "mic.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(muted ? C.danger : .secondary.opacity(0.6))
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .help(store.userMuted ? "You're muted — tap to unmute" : "Tap to mute (Eve keeps talking, you stay quiet)")
                .transition(.opacity.combined(with: .scale))
            }

            Button(action: pickImage) {
                ZStack {
                    Circle().fill(C.surfaceHi)
                    Circle().stroke(C.hairline, lineWidth: 1)
                    Image(systemName: store.pendingImages.isEmpty ? "photo" : "photo.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(store.pendingImages.isEmpty ? .secondary.opacity(0.4) : C.think)
                    if !store.pendingImages.isEmpty {
                        Text("\(store.pendingImages.count)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(C.think)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(C.bg)
                            .clipShape(Capsule())
                            .offset(x: 14, y: -14)
                    }
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .help("Attach image — Eve uses llava (vision)")

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DIRECTIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    TextField(
                        "",
                        text: $text,
                        prompt: Text("Send a directive...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    )
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.92))
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit {
                        // If the slash popup is open with at least one match,
                        // Enter runs the top match instead of submitting the
                        // raw "/whatever" text to Eve.
                        if let _ = slashQuery, let first = slashCommands.first {
                            runSlashCommand(first)
                            return
                        }
                        // If the mention popup is open, Enter inserts the top
                        // candidate rather than sending half-formed @text.
                        if let _ = mentionQuery, let first = mentionCandidates.first {
                            insertMention(first)
                            return
                        }
                        onSubmit()
                    }
                    .onChange(of: text) { _, new in
                        handleTextChange(new)
                    }
                }

                Spacer(minLength: 0)

                if store.eveStatus == .speaking {
                    Button(action: { store.voice.stopSpeaking(); store.eveStatus = .idle }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(C.bg)
                            .frame(width: 30, height: 30)
                            .background(C.danger)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop Eve speaking")
                    .transition(.scale.combined(with: .opacity))
                } else if !text.isEmpty {
                    Button(action: onSubmit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(C.bg)
                            .frame(width: 30, height: 30)
                            .background(C.eve)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(C.surfaceHi)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(inputFocused ? C.eve.opacity(0.4) : C.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if usesLauncher {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showLauncher.toggle()
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: showLauncher ? "xmark" : "square.grid.2x2")
                            .font(.system(size: 13, weight: .semibold))
                        Text("HUB")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(showLauncher ? C.eve : .secondary.opacity(0.38))
                    .frame(width: 56, height: 46)
                    .background(showLauncher ? C.eve.opacity(0.14) : C.surfaceHi)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(showLauncher ? C.eve.opacity(0.32) : C.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(C.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(C.hairline, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 30, y: 8)
        .frame(maxWidth: 980)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: NSImage.self) {
                    _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                        guard let img = obj as? NSImage,
                              let tiff = img.tiffRepresentation,
                              let bmp  = NSBitmapImageRep(data: tiff),
                              let png  = bmp.representation(using: .png, properties: [:])
                        else { return }
                        let b64 = png.base64EncodedString()
                        DispatchQueue.main.async { store.pendingImages.append(b64) }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { store.attachImage(at: url) }
                    }
                }
            }
            return true
        }
    }

    private func toggleMic() {
        if store.fluidListening || store.eveStatus == .listening {
            store.stopListening()
            store.voice.stopSpeaking()
        } else {
            store.startListening()
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.image, .jpeg, .png, .gif, .heic]
        panel.message                 = "Attach images for Eve to see (vision via llava)"
        panel.prompt                  = "Attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                store.attachImage(at: url)
            }
        }
    }

    // MARK: - Mention + slash detection
    //
    // Called every keystroke via .onChange(of: text) on the field.
    func handleTextChange(_ new: String) {
        // Slash takes precedence and only when input begins with "/"
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") && !trimmed.contains(" ") {
            withAnimation(.easeOut(duration: 0.12)) {
                slashQuery = trimmed
                mentionQuery = nil
            }
            return
        }

        // Mention query
        if let (_, q) = MentionCatalog.detectQuery(in: new) {
            withAnimation(.easeOut(duration: 0.12)) {
                mentionQuery = q
                slashQuery = nil
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                mentionQuery = nil
                slashQuery = nil
            }
        }
    }

    private func insertMention(_ candidate: MentionCandidate) {
        text = MentionCatalog.insert(candidate, into: text)
        withAnimation(.easeOut(duration: 0.12)) { mentionQuery = nil }
    }

    private func runSlashCommand(_ cmd: SlashCommand) {
        // Templates insert their body into the input rather than firing an action.
        if let body = TemplateLibrary.body(for: cmd.id) {
            text = body
            withAnimation(.easeOut(duration: 0.12)) { slashQuery = nil }
            return
        }

        switch cmd.id {
        case "/new", "/end":
            store.newConversation()
        case "/local":
            store.preferLocalBrain = true
        case "/cloud":
            store.preferLocalBrain = false
        case "/pop":
            if let cid = store.currentConversationId {
                openWindow(id: "conversation-detail", value: cid)
            }
        case "/clear":
            store.messages.removeAll()
        case "/help":
            // Stuff a help message into the chat — fast feedback, no API call.
            let help = """
            Slash commands:
              /new      end thread, start fresh
              /end      same as /new
              /local    use local Ollama brain
              /cloud    use nexus-web (Grok + tools)
              /pop      pop the active thread into a window
              /clear    clear visible messages
              /help     this list
            Type @ for mentions across operations, agents, records, conversations, directives, and memories.
            """
            store.messages.append(ChatMessage(role: .assistant, content: help, brain: "local"))
        default:
            break
        }
        text = ""
        withAnimation(.easeOut(duration: 0.12)) { slashQuery = nil }
    }
}

// MARK: - Command launcher

struct CommandLauncher: View {
    @Binding var isShowing: Bool
    @Binding var activePanel: MainView.PanelType
    @ObservedObject var store: LumenStore

    struct Tile: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let sub: String
        let available: Bool
        let action: () -> Void
    }

    private var tiles: [Tile] {
        [
            Tile(icon: "person.badge.shield.checkmark.fill", label: "AGENTS",     sub: "\(store.agents.count) UNITS",      available: true)  { activePanel = .agents;     isShowing = false },
            Tile(icon: "bolt.fill",                           label: "OPS",        sub: "\(store.operations.count) ACTIVE", available: true)  { activePanel = .operations; isShowing = false },
            Tile(icon: "shield.lefthalf.filled",              label: "DIRECTIVES", sub: "\(store.directives.count) LOADED", available: true)  { activePanel = .directives; isShowing = false; Task { await store.fetchDirectives() } },
            Tile(icon: "brain.head.profile",                  label: "MEMORY",     sub: "\(store.memories.count) ENTRIES",  available: true)  { activePanel = .memory;     isShowing = false; Task { await store.fetchMemories() } },
            Tile(icon: "bubble.left.and.bubble.right.fill",   label: "CHATS",      sub: "HISTORY",                          available: true)  { activePanel = .chats;      isShowing = false; Task { await store.fetchConversations() } },
            Tile(icon: "folder.fill",                         label: "FILES",      sub: "LOCAL ACCESS",                     available: true)  { activePanel = .files;      isShowing = false },
            Tile(icon: "cpu.fill",                            label: "SYSTEM",     sub: "ACCESS POINTS",                    available: true)  { activePanel = .system;     isShowing = false },
            Tile(icon: "gearshape.fill",                      label: "SETTINGS",   sub: "ACCOUNT",                          available: true)  { activePanel = .settings;   isShowing = false },
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COMMAND HUB")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(4)
                Spacer()
                Button { withAnimation { isShowing = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { idx, tile in
                    LauncherTile(tile: tile, index: idx)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(C.surface.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.hairline, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.7), radius: 40, y: -12)
        .padding(.horizontal, 28)
    }
}

private struct LauncherTile: View {
    let tile: CommandLauncher.Tile
    let index: Int
    @State private var appeared = false
    @State private var hovered  = false

    var body: some View {
        Button(action: tile.action) {
            VStack(spacing: 10) {
                Image(systemName: tile.icon)
                    .font(.system(size: 20))
                    .foregroundColor(tileColor)
                VStack(spacing: 2) {
                    Text(tile.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(hovered && tile.available ? .primary : .secondary.opacity(tile.available ? 0.55 : 0.2))
                        .tracking(2)
                    Text(tile.sub)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 8).fill(bgColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
            .opacity(tile.available ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!tile.available)
        .onHover { hovered = $0 }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72).delay(Double(index) * 0.045)) {
                appeared = true
            }
        }
    }

    private var tileColor: Color {
        guard tile.available else { return .secondary.opacity(0.15) }
        return hovered ? C.eve : .secondary.opacity(0.4)
    }
    private var bgColor: Color {
        guard tile.available && hovered else { return .secondary.opacity(0.03) }
        return C.eve.opacity(0.1)
    }
    private var borderColor: Color {
        guard tile.available else { return .secondary.opacity(0.05) }
        return hovered ? C.eve.opacity(0.35) : .secondary.opacity(0.07)
    }
}

// MARK: - Panel sheet (rises from bottom)

struct PanelSheet: View {
    let type: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(C.surfaceHi)
                        .frame(width: 32, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    switch type {
                    case .agents:     AgentPanel(store: store, onDismiss: onDismiss)
                    case .operations: OpsPanel2(store: store, onDismiss: onDismiss)
                    case .directives: DirectivesPanel(store: store, onDismiss: onDismiss)
                    case .memory:     MemoryPanel(store: store, onDismiss: onDismiss)
                    case .chats:      ChatsPanel(store: store, onDismiss: onDismiss)
                    case .nexusMap:   NexusMapView(store: store)
                    case .files:      FilesPanel(store: store, onDismiss: onDismiss)
                    case .code:       CodePanel(store: store, onClose: onDismiss)
                    case .system:     SystemPanel(store: store, onDismiss: onDismiss)
                    case .settings:   SettingsPanel(store: store, auth: auth, onDismiss: onDismiss)
                    case .none:       EmptyView()
                    }
                }
                .frame(maxWidth: min(proxy.size.width - 36, 1240))
                .frame(height: min(max(proxy.size.height * 0.82, 620), 820))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(C.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(C.hairline, lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.6), radius: 50, y: -20)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct WorkspaceInspector: View {
    let type: MainView.PanelType
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch type {
            case .agents:
                AgentPanel(store: store, onDismiss: onDismiss)
            case .operations:
                OpsPanel2(store: store, onDismiss: onDismiss)
            case .chats:
                ChatsPanel(store: store, onDismiss: onDismiss)
            case .files:
                FilesPanel(store: store, onDismiss: onDismiss)
            case .code:
                CodePanel(store: store, onClose: onDismiss)
            case .system:
                SystemPanel(store: store, onDismiss: onDismiss)
            case .settings:
                SettingsPanel(store: store, auth: auth, onDismiss: onDismiss)
            case .directives:
                DirectivesPanel(store: store, onDismiss: onDismiss)
            case .memory:
                MemoryPanel(store: store, onDismiss: onDismiss)
            case .nexusMap:
                NexusMapView(store: store)
            case .none:
                EmptyView()
            }
        }
        .background(SurfaceCard(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Panel: Agents

struct AgentPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void
    @Environment(\.openWindow) private var openWindow

    @State private var selectedId: String? = nil
    @State private var scanning: String? = nil
    @State private var toggling: String? = nil

    private var selectedAgent: AgentStatus? {
        if let selectedId {
            return store.agents.first(where: { $0.agentId == selectedId })
        }
        return store.agents.first
    }

    var body: some View {
        GeometryReader { proxy in
            let splitLayout = proxy.size.width > 860

            VStack(spacing: 0) {
                SheetHeader(title: "AGENT ROSTER", subtitle: "\(store.agents.count) UNITS", onDismiss: onDismiss)

                if splitLayout {
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(store.agents) { agent in
                                    AgentRow(agent: agent, isSelected: (selectedId ?? selectedAgent?.agentId) == agent.agentId)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedId = agent.agentId }
                                        .contextMenu {
                                            Button("Open in New Window") { openWindow(id: "agent-detail", value: agent.agentId) }
                                            Button(agent.status == "active" ? "Set Standby" : "Activate") { toggle(agent: agent) }
                                            Button("Run Scan") { runScan(for: agent) }
                                        }
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .frame(width: 340)
                        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1), alignment: .trailing)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let agent = selectedAgent {
                                    AgentDetailCard(
                                        agent: agent,
                                        details: store.agentRecords[agent.agentId] ?? [:],
                                        activity: store.activityByAgent[agent.agentId] ?? [],
                                        chat: store.agentChats[agent.agentId] ?? [],
                                        isSendingChat: store.agentChatSending == agent.agentId,
                                        isScanning: scanning == agent.agentId,
                                        isToggling: toggling == agent.agentId,
                                        onRunScan: { runScan(for: agent) },
                                        onToggle: { toggle(agent: agent) },
                                        onSendChat: { msg in Task { await store.sendAgentChat(agentId: agent.agentId, message: msg) } },
                                        onClearChat: { store.clearAgentChat(agentId: agent.agentId) }
                                    )
                                } else {
                                    EmptyInspectorState(title: "No agents loaded", detail: "Dashboard data has not returned any agent records yet.")
                                }
                            }
                            .padding(22)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(store.agents) { agent in
                                AgentRow(agent: agent, isSelected: selectedId == agent.agentId)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25)) {
                                            selectedId = selectedId == agent.agentId ? nil : agent.agentId
                                        }
                                    }
                                    .contextMenu {
                                        Button("Open in New Window") { openWindow(id: "agent-detail", value: agent.agentId) }
                                    }
                                if selectedId == agent.agentId {
                                    AgentDetailCard(
                                        agent: agent,
                                        details: store.agentRecords[agent.agentId] ?? [:],
                                        activity: store.activityByAgent[agent.agentId] ?? [],
                                        chat: store.agentChats[agent.agentId] ?? [],
                                        isSendingChat: store.agentChatSending == agent.agentId,
                                        isScanning: scanning == agent.agentId,
                                        isToggling: toggling == agent.agentId,
                                        onRunScan: { runScan(for: agent) },
                                        onToggle: { toggle(agent: agent) },
                                        onSendChat: { msg in Task { await store.sendAgentChat(agentId: agent.agentId, message: msg) } },
                                        onClearChat: { store.clearAgentChat(agentId: agent.agentId) }
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .onAppear {
            if selectedId == nil {
                selectedId = store.agents.first?.agentId
            }
        }
        .onAppear {
            if selectedId == nil { selectedId = store.agents.first?.agentId }
            if let id = selectedId { Task { await store.fetchAgentActivity(id: id) } }
        }
        .onChange(of: selectedId) { _, new in
            if let id = new { Task { await store.fetchAgentActivity(id: id) } }
        }
    }

    private func runScan(for agent: AgentStatus) {
        scanning = agent.agentId
        Task {
            await LumenAPIManager.shared.runAgent(id: agent.agentId)
            await store.fetchDashboard()
            await store.fetchAgentActivity(id: agent.agentId)
            scanning = nil
        }
    }

    private func toggle(agent: AgentStatus) {
        toggling = agent.agentId
        let newStatus = agent.status == "active" ? "standby" : "active"
        Task {
            await LumenAPIManager.shared.setAgentStatus(id: agent.agentId, status: newStatus)
            await store.fetchDashboard()
            await store.fetchAgentActivity(id: agent.agentId)
            toggling = nil
        }
    }
}

private struct AgentRow: View {
    let agent: AgentStatus
    let isSelected: Bool
    @State private var hovered = false

    private var statusColor: Color {
        switch agent.status {
        case "active":    return C.listen
        case "deployed":  return C.eve
        default:          return .secondary.opacity(0.55)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(statusColor).frame(width: 6, height: 6).shadow(color: statusColor, radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                    Spacer()
                    Text(agent.status.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor.opacity(0.08), in: Capsule())
                }
                Text(agent.role)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.6))
                Text(agent.lastAction)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Image(systemName: isSelected ? "chevron.up" : "chevron.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
        .softRowSurface(isSelected: isSelected, isHovered: hovered, accent: statusColor)
        .onHover { hovered = $0 }
    }
}

struct AgentDetailCard: View {
    let agent: AgentStatus
    let details: [String: String]
    let activity: [AgentActivity]
    let chat: [ChatMessage]
    let isSendingChat: Bool
    let isScanning: Bool
    let isToggling: Bool
    let onRunScan: () -> Void
    let onToggle: () -> Void
    let onSendChat: (String) -> Void
    let onClearChat: () -> Void

    @State private var chatInput: String = ""

    // Activity-derived metrics
    private var scanCount: Int {
        activity.filter { $0.action.lowercased().contains("scan") }.count
    }
    private var findingCount: Int {
        activity.filter { $0.action.lowercased().contains("finding") }.count
    }
    private var failureCount: Int {
        activity.filter { $0.action.lowercased().contains("fail") || $0.action.lowercased().contains("error") }.count
    }
    private var lastActionRelative: String {
        guard let recent = activity.first?.createdAt else { return "—" }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFull.date(from: recent) ?? ISO8601DateFormatter().date(from: recent)
        return date?.lumenRelative ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Four-tile metric grid for richer at-a-glance.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DetailMetric(title: "FINDINGS", value: "\(agent.totalFindings)", accent: agent.totalFindings > 0 ? C.listen : .primary)
                DetailMetric(title: "STATUS",   value: agent.status.uppercased(), accent: agent.status == "active" ? C.listen : C.eve)
                DetailMetric(title: "SCANS",    value: "\(scanCount)", accent: scanCount > 0 ? C.eve : .secondary)
                DetailMetric(title: "LAST SEEN", value: lastActionRelative, accent: .primary)
            }

            // Activity breakdown bar
            if !activity.isEmpty {
                HStack(spacing: 8) {
                    activityBadge(label: "EVENTS", value: "\(activity.count)", color: C.eve)
                    if findingCount > 0 {
                        activityBadge(label: "FINDINGS", value: "\(findingCount)", color: C.listen)
                    }
                    if failureCount > 0 {
                        activityBadge(label: "FAILED", value: "\(failureCount)", color: C.danger)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            DetailSection(title: "ROLE", text: agent.role)
            DetailSection(title: "LAST ACTION", text: agent.lastAction)

            // Activity log
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ACTIVITY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Spacer()
                    Text("\(activity.count) EVENTS")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(1)
                }

                if activity.isEmpty {
                    Text("No activity yet. Run a scan or activate the agent.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.58))
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(activity.prefix(15)) { ev in
                            ActivityRow(item: ev)
                        }
                    }
                }
            }
            .padding(10)
            .background(C.surfaceHi)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(C.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            DetailSection(title: "AGENT ID", text: agent.agentId)
            KeyValueSection(title: "FULL RECORD", values: details)

            // Direct comms with this agent's persona
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DIRECT COMMS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Spacer()
                    if !chat.isEmpty {
                        Button(action: onClearChat) {
                            Text("CLEAR")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.primary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if chat.isEmpty {
                    Text("Open channel to \(agent.name). Each agent uses its own persona, role, and directives.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.58))
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 4) {
                        ForEach(chat) { m in AgentChatRow(message: m) }
                        if isSendingChat {
                            HStack {
                                ProgressView().controlSize(.mini).tint(C.eve)
                                Text("\(agent.name) is responding…")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Send to \(agent.name)…", text: $chatInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(C.surfaceHi)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit(submitChat)

                    Button(action: submitChat) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(C.eve)
                            .frame(width: 30, height: 30)
                            .background(C.eve.opacity(0.12))
                            .overlay(Capsule().strokeBorder(C.eve.opacity(0.4), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || isSendingChat)
                }
            }
            .padding(10)
            .background(C.surfaceHi)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(C.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                PanelActionButton(
                    label: isScanning ? "SCANNING..." : "RUN SCAN",
                    color: C.listen,
                    disabled: isScanning || isToggling,
                    action: onRunScan
                )
                PanelActionButton(
                    label: isToggling ? "UPDATING..." : (agent.status == "active" ? "SET STANDBY" : "ACTIVATE"),
                    color: agent.status == "active" ? C.think : C.eve,
                    disabled: isScanning || isToggling,
                    action: onToggle
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(C.surface)
        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    private func submitChat() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSendingChat else { return }
        chatInput = ""
        onSendChat(text)
    }

    @ViewBuilder
    private func activityBadge(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08), in: Capsule())
    }
}

private struct AgentChatRow: View {
    let message: ChatMessage
    private var isAgent: Bool { message.role == .assistant }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(isAgent ? "AGENT" : "YOU")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(isAgent ? C.eve.opacity(0.7) : .secondary.opacity(0.6))
                .tracking(1.5)
                .frame(width: 36, alignment: .leading)
                .padding(.top, 3)
            Text(message.content)
                .font(.system(size: 11))
                .foregroundColor(isAgent ? .secondary.opacity(0.85) : .secondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(isAgent ? C.eve.opacity(0.06) : C.surfaceHi)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((isAgent ? C.eve : Color.primary).opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActivityRow: View {
    let item: AgentActivity

    private var actionColor: Color {
        switch item.action {
        case "scan_completed":   return C.listen
        case "scan_started":     return C.eve
        case "scan_failed":      return C.danger
        case "finding_created":  return C.think
        case "batch_completed":  return .secondary.opacity(0.45)
        case "status_change":    return C.eve
        default:                 return .secondary.opacity(0.4)
        }
    }

    private var relativeTime: String {
        guard !item.createdAt.isEmpty else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: item.createdAt) ?? ISO8601DateFormatter().date(from: item.createdAt) else { return "" }
        let s = -date.timeIntervalSinceNow
        if s < 60    { return "\(Int(s))s ago" }
        if s < 3600  { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(actionColor).frame(width: 5, height: 5).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.summary)
                    .font(.system(size: 10))
                    .foregroundColor(.primary.opacity(0.78))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(relativeTime)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.58))
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(C.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Panel: Operations

struct OpsPanel2: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void
    @Environment(\.openWindow) private var openWindow

    @State private var selectedId: String? = nil
    @State private var updating: String? = nil

    private var selectedOperation: OperationItem? {
        if let selectedId {
            return store.operations.first(where: { $0.operationId == selectedId })
        }
        return store.operations.first
    }

    var body: some View {
        GeometryReader { proxy in
            let splitLayout = proxy.size.width > 860

            VStack(spacing: 0) {
                SheetHeader(
                    title: "OPERATIONS",
                    subtitle: "\(store.operations.count) ACTIVE",
                    onDismiss: onDismiss,
                    onPopOut: selectedOperation == nil ? nil : { openSelectedOperation() }
                )

                if splitLayout {
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(store.operations) { op in
                                    OpsRow2(op: op, isSelected: (selectedId ?? selectedOperation?.operationId) == op.operationId)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedId = op.operationId }
                                        .contextMenu {
                                            Button("Open in New Window") { openWindow(id: "operation-detail", value: op.operationId) }
                                            Button("Set Active")   { update(op: op, status: "active") }
                                            Button("Set Paused")   { update(op: op, status: "paused") }
                                            Button("Set Complete") { update(op: op, status: "complete") }
                                        }
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .frame(width: 340)
                        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1), alignment: .trailing)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let op = selectedOperation {
                                    OpsDetailCard(
                                        op: op,
                                        details: store.operationRecords[op.operationId] ?? [:],
                                        records: store.recordsByOp[op.operationId] ?? [],
                                        briefs: store.briefsByOp[op.operationId] ?? [:],
                                        generatingBrief: store.briefGenerating,
                                        isUpdating: updating == op.operationId,
                                        onSetStatus: { update(op: op, status: $0) },
                                        onAddRecord: { title, content, type in
                                            Task { await store.addRecord(opId: op.operationId, title: title, content: content, type: type) }
                                        },
                                        onRegenerateBrief: { kind in
                                            Task { await store.regenerateBrief(opId: op.operationId, kind: kind) }
                                        }
                                    )
                                } else {
                                    EmptyInspectorState(title: "No operations loaded", detail: "Dashboard data has not returned any operation records yet.")
                                }
                            }
                            .padding(22)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(store.operations) { op in
                                OpsRow2(op: op, isSelected: selectedId == op.operationId)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25)) {
                                            selectedId = selectedId == op.operationId ? nil : op.operationId
                                        }
                                    }
                                    .contextMenu {
                                        Button("Open in New Window") { openWindow(id: "operation-detail", value: op.operationId) }
                                    }
                                if selectedId == op.operationId {
                                    OpsDetailCard(
                                        op: op,
                                        details: store.operationRecords[op.operationId] ?? [:],
                                        records: store.recordsByOp[op.operationId] ?? [],
                                        briefs: store.briefsByOp[op.operationId] ?? [:],
                                        generatingBrief: store.briefGenerating,
                                        isUpdating: updating == op.operationId,
                                        onSetStatus: { update(op: op, status: $0) },
                                        onAddRecord: { title, content, type in
                                            Task { await store.addRecord(opId: op.operationId, title: title, content: content, type: type) }
                                        },
                                        onRegenerateBrief: { kind in
                                            Task { await store.regenerateBrief(opId: op.operationId, kind: kind) }
                                        }
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .onAppear {
            if selectedId == nil {
                selectedId = store.operations.first?.operationId
            }
            Task { await store.fetchOperations() }
            if let id = selectedId {
                Task { await store.fetchRecords(opId: id); await store.fetchBriefs(opId: id) }
            }
        }
        .onChange(of: selectedId) { _, new in
            if let id = new {
                Task { await store.fetchRecords(opId: id); await store.fetchBriefs(opId: id) }
            }
        }
    }

    private func update(op: OperationItem, status: String) {
        updating = op.operationId
        Task {
            await LumenAPIManager.shared.setOpStatus(id: op.operationId, status: status)
            await store.fetchOperations()
            updating = nil
        }
    }

    private func openSelectedOperation() {
        guard let operationId = selectedOperation?.operationId else { return }
        openWindow(id: "operation-detail", value: operationId)
    }
}

private struct OpsRow2: View {
    let op: OperationItem
    let isSelected: Bool
    @State private var hovered = false

    private var priorityColor: Color {
        switch op.priority {
        case "high":   return C.danger
        case "medium": return C.think
        default:       return .secondary.opacity(0.55)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 1).fill(priorityColor).frame(width: 2, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(op.name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                    Spacer()
                    Text(op.status.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(op.status == "active" ? C.listen : .secondary.opacity(0.58))
                }
                Text(op.priority.uppercased() + " PRIORITY")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(priorityColor.opacity(0.7))
                    .tracking(1)
            }
            Image(systemName: isSelected ? "chevron.up" : "chevron.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .softRowSurface(isSelected: isSelected, isHovered: hovered, accent: priorityColor)
        .onHover { hovered = $0 }
    }
}

private struct OpsDetailCard: View {
    let op: OperationItem
    let details: [String: String]
    let records: [OperationRecord]
    let briefs: [String: OperationBrief]
    let generatingBrief: String?
    let isUpdating: Bool
    let onSetStatus: (String) -> Void
    let onAddRecord: (String, String, String) -> Void  // title, content, type
    let onRegenerateBrief: (String) -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var activeBriefKind: String = "summary"
    private let briefKinds = ["summary", "actions", "next-steps", "themes", "contradictions"]
    private func briefLabel(_ k: String) -> String {
        switch k {
        case "summary": return "SUMMARY"
        case "actions": return "ACTIONS"
        case "next-steps": return "NEXT STEPS"
        case "themes": return "THEMES"
        case "contradictions": return "GAPS"
        default: return k.uppercased()
        }
    }

    @State private var showAddForm = false
    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var newType = "note"
    private let statuses = ["active", "planning", "complete", "standby"]
    private let recordTypes = ["note", "intel", "finding", "data", "alert"]

    // Derived counts for the at-a-glance bar
    private var pinnedCount: Int { records.filter(\.pinned).count }
    private var criticalCount: Int { records.filter { $0.priority.lowercased() == "critical" || $0.priority.lowercased() == "high" }.count }
    private var briefsCount: Int { briefs.values.filter { !$0.content.isEmpty }.count }
    private var recordsByType: [(String, Int)] {
        Dictionary(grouping: records, by: \.type)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Three-row metric grid: 6 tiles total for richer at-a-glance.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DetailMetric(title: "CODENAME",  value: op.codename, accent: C.eve)
                DetailMetric(title: "PRIORITY",  value: op.priority.uppercased(), accent: priorityColor)
                DetailMetric(title: "STATUS",    value: op.status.uppercased(), accent: op.status == "active" ? C.listen : .primary)
                DetailMetric(title: "RECORDS",   value: "\(records.count)", accent: C.think)
                DetailMetric(title: "BRIEFS",    value: "\(briefsCount)/\(briefKinds.count)", accent: C.eve)
                DetailMetric(title: "PINNED",    value: "\(pinnedCount)", accent: pinnedCount > 0 ? C.listen : .secondary)
            }

            // At-a-glance stripe — type distribution + critical count
            if !records.isEmpty {
                HStack(spacing: 10) {
                    if criticalCount > 0 {
                        statBadge(label: "CRITICAL", value: "\(criticalCount)", color: .red)
                    }
                    ForEach(recordsByType.prefix(4), id: \.0) { typ, n in
                        statBadge(label: typ.uppercased(), value: "\(n)", color: typeColor(typ))
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            PanelActionButton(
                label: "OPEN IN WINDOW",
                color: C.eve,
                disabled: false,
                action: { openWindow(id: "operation-detail", value: op.operationId) }
            )

            if !op.description.isEmpty {
                DetailSection(title: "DESCRIPTION", text: op.description)
            }

            // Eve Briefs — auto-generated analysis
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EVE BRIEFS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Spacer()
                    let isGenerating = generatingBrief == "\(op.operationId):\(activeBriefKind)"
                    let canGenerate  = !isGenerating && !records.isEmpty
                    Button(action: { onRegenerateBrief(activeBriefKind) }) {
                        HStack(spacing: 6) {
                            if isGenerating {
                                ProgressView().controlSize(.mini).tint(C.eve)
                            } else {
                                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                            }
                            Text(isGenerating ? "GENERATING…" : (briefs[activeBriefKind] == nil ? "GENERATE" : "REGENERATE"))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                        }
                        .foregroundColor(canGenerate ? .white : .secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(canGenerate ? C.eve : Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGenerate)
                    .help(records.isEmpty ? "Add at least one record before generating a brief" : "Generate this brief from records via Grok")
                }

                // Brief kind picker
                HStack(spacing: 4) {
                    ForEach(briefKinds, id: \.self) { kind in
                        let hasBrief = briefs[kind] != nil
                        Button(action: { activeBriefKind = kind }) {
                            HStack(spacing: 4) {
                                Text(briefLabel(kind))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .tracking(1.5)
                                if hasBrief {
                                    Circle().fill(C.eve).frame(width: 4, height: 4)
                                }
                            }
                            .foregroundColor(activeBriefKind == kind ? C.eve : .secondary.opacity(0.5))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(activeBriefKind == kind ? C.eve.opacity(0.10) : Color.white.opacity(0.03), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                if let brief = briefs[activeBriefKind] {
                    Text(brief.content)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(records.isEmpty
                         ? "Add a record first — Eve needs context to write briefs."
                         : "No \(briefLabel(activeBriefKind).lowercased()) yet. Tap GENERATE.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.6))
                        .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 6)

            // Records list
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RECORDS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(2)
                    Spacer()
                    Button(action: { withAnimation { showAddForm.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: showAddForm ? "minus" : "plus").font(.system(size: 9, weight: .bold))
                            Text(showAddForm ? "CLOSE" : "ADD").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                        }
                        .foregroundColor(C.listen)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(C.listen.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if showAddForm {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Record title", text: $newTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        TextEditor(text: $newContent)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 11))
                            .frame(minHeight: 60, maxHeight: 100)
                            .padding(6)
                            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        HStack {
                            Picker("", selection: $newType) {
                                ForEach(recordTypes, id: \.self) { t in
                                    Text(t.uppercased()).font(.system(size: 9, design: .monospaced)).tag(t)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            Spacer()
                            Button("SAVE") {
                                guard !newTitle.isEmpty else { return }
                                onAddRecord(newTitle, newContent, newType)
                                newTitle = ""; newContent = ""; newType = "note"
                                withAnimation { showAddForm = false }
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(C.eve, in: Capsule())
                            .buttonStyle(.plain)
                            .disabled(newTitle.isEmpty)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if records.isEmpty && !showAddForm {
                    Text("No records yet. Add intel, findings, or notes.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.58))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 4) {
                        ForEach(records) { r in
                            RecordRow(record: r)
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(statuses, id: \.self) { status in
                    PanelActionButton(
                        label: isUpdating ? "..." : status.uppercased(),
                        color: op.status == status ? C.listen : .secondary.opacity(0.6),
                        disabled: isUpdating || op.status == status,
                        action: { onSetStatus(status) }
                    )
                }
            }

            KeyValueSection(title: "FULL OPERATION DATASET", values: details)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var priorityColor: Color {
        switch op.priority {
        case "high":
            return C.danger
        case "medium":
            return C.think
        default:
            return .secondary.opacity(0.6)
        }
    }

    private func typeColor(_ t: String) -> Color {
        switch t.lowercased() {
        case "intel":   return C.listen
        case "finding": return C.danger
        case "data":    return C.think
        case "alert":   return .red
        case "note":    return .secondary
        default:        return C.eve
        }
    }

    @ViewBuilder
    private func statBadge(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08), in: Capsule())
    }
}

private struct RecordRow: View {
    let record: OperationRecord

    private var typeColor: Color {
        switch record.type {
        case "alert":   return C.danger
        case "intel":   return C.eve
        case "finding": return C.listen
        case "data":    return C.think
        default:        return .secondary.opacity(0.5)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                if record.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                }
                Text(record.type.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(typeColor)
                    .tracking(1)
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(2)
                if !record.content.isEmpty {
                    Text(record.content)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    Text(record.priority.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(priorityColor)
                    Text("·")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(record.source.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.58))
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var priorityColor: Color {
        switch record.priority {
        case "critical": return C.danger
        case "high":     return C.think
        case "low":      return .secondary.opacity(0.58)
        default:         return .secondary.opacity(0.5)
        }
    }
}

// MARK: - Shared panel action button

private struct PanelActionButton: View {
    let label: String
    let color: Color
    let disabled: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(disabled ? .secondary.opacity(0.48) : (hovered ? color : color.opacity(0.65)))
                .tracking(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (hovered && !disabled) ? color.opacity(0.10) : color.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
    }
}

// MARK: - Panel: Directives

struct DirectivesPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void
    @State private var selectedId: String? = nil
    @State private var filter: String = "all"  // all | directive | protocol | rule
    @State private var showCreate = false
    @State private var newType = "directive"
    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var newTarget = "all"
    @State private var newPriority = 5

    private var filtered: [DirectiveItem] {
        let f = filter == "all" ? store.directives : store.directives.filter { $0.type == filter }
        return f.sorted { $0.priority > $1.priority }
    }

    private var selected: DirectiveItem? {
        store.directives.first { $0.id == selectedId } ?? filtered.first
    }

    var body: some View {
        GeometryReader { proxy in
            let split = proxy.size.width > 760

            VStack(spacing: 0) {
                SheetHeader(title: "DIRECTIVES", subtitle: "\(store.directives.count) LOADED · \(store.directives.filter { $0.isActive }.count) ACTIVE", onDismiss: onDismiss)

                HStack(spacing: 6) {
                    ForEach(["all", "directive", "protocol", "rule"], id: \.self) { f in
                        Button(action: { filter = f }) {
                            Text(f.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(filter == f ? .white : .secondary.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(filter == f ? C.eve.opacity(0.25) : C.surfaceHi)
                                .overlay(Capsule().strokeBorder(filter == f ? C.eve.opacity(0.5) : C.hairline, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button(action: { withAnimation { showCreate.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCreate ? "minus" : "plus").font(.system(size: 9, weight: .bold))
                            Text(showCreate ? "CLOSE" : "NEW").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                        }
                        .foregroundColor(C.eve)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(C.eve.opacity(0.12))
                        .overlay(Capsule().strokeBorder(C.eve.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

                if showCreate {
                    DirectiveCreateForm(
                        type: $newType,
                        title: $newTitle,
                        content: $newContent,
                        target: $newTarget,
                        priority: $newPriority,
                        onSave: {
                            guard !newTitle.isEmpty, !newContent.isEmpty else { return }
                            Task { await store.createDirective(type: newType, title: newTitle, content: newContent, priority: newPriority, target: newTarget) }
                            newTitle = ""; newContent = ""; newType = "directive"; newTarget = "all"; newPriority = 5
                            withAnimation { showCreate = false }
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                }

                if split {
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filtered) { d in
                                    DirectiveRow(item: d, isSelected: (selectedId ?? selected?.id) == d.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedId = d.id }
                                }
                            }
                            .padding(14)
                        }
                        .frame(width: 320)
                        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1), alignment: .trailing)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let d = selected {
                                    DirectiveDetail(item: d, onToggle: { Task { await store.toggleDirective(d) } })
                                } else {
                                    EmptyInspectorState(title: "No directives", detail: "Create directives in the web app to control Eve's behavior.")
                                }
                            }
                            .padding(22)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered) { d in
                                DirectiveRow(item: d, isSelected: selectedId == d.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25)) {
                                            selectedId = selectedId == d.id ? nil : d.id
                                        }
                                    }
                                if selectedId == d.id {
                                    DirectiveDetail(item: d, onToggle: { Task { await store.toggleDirective(d) } })
                                        .padding(.horizontal, 8)
                                        .padding(.bottom, 8)
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .task { await store.fetchDirectives() }
    }
}

private struct DirectiveRow: View {
    let item: DirectiveItem
    let isSelected: Bool

    private var typeColor: Color {
        switch item.type { case "protocol": return C.think; case "rule": return C.danger; default: return C.eve }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(item.isActive ? typeColor : C.surfaceHi).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary.opacity(item.isActive ? 0.9 : 0.4))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.type.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(typeColor)
                    Text("· P\(item.priority)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.58))
                    if !item.isActive {
                        Text("· OFF")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.58))
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(isSelected ? Color.secondary.opacity(0.14) : C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? typeColor.opacity(0.4) : C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DirectiveDetail: View {
    let item: DirectiveItem
    let onToggle: () -> Void
    @EnvironmentObject var store: LumenStore

    private var typeColor: Color {
        switch item.type { case "protocol": return C.think; case "rule": return C.danger; default: return C.eve }
    }

    /// Rough "weight" indicator — combines priority and active state into a
    /// single visible number so the Director can see at a glance how heavily
    /// this directive will steer Eve's behavior.
    private var influenceScore: Int {
        guard item.isActive else { return 0 }
        return item.priority * 10
    }

    private var siblingsOfType: Int {
        store.directives.filter { $0.type == item.type }.count
    }

    private var totalActive: Int {
        store.directives.filter(\.isActive).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.type.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(typeColor)
                    Text(item.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.92))
                }
                Spacer()
                Button(action: onToggle) {
                    Text(item.isActive ? "DEACTIVATE" : "ACTIVATE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(item.isActive ? C.danger : C.listen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(item.isActive ? C.danger.opacity(0.1) : C.listen.opacity(0.1))
                        .overlay(Capsule().strokeBorder(item.isActive ? C.danger.opacity(0.5) : C.listen.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Density: 4 metric tiles in a row
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DetailMetric(title: "STATE",     value: item.isActive ? "ACTIVE" : "OFF",
                             accent: item.isActive ? C.listen : .secondary)
                DetailMetric(title: "PRIORITY",  value: "P\(item.priority)",
                             accent: item.priority >= 8 ? C.danger : (item.priority >= 5 ? C.think : .secondary))
                DetailMetric(title: "TARGET",    value: item.target.isEmpty ? "ALL" : item.target.uppercased(),
                             accent: typeColor)
                DetailMetric(title: "INFLUENCE", value: item.isActive ? "\(influenceScore)" : "—",
                             accent: item.isActive ? typeColor : .secondary)
            }

            // At-a-glance bar — context across the full directive set
            HStack(spacing: 8) {
                statBadge(label: "OF \(item.type.uppercased())S", value: "\(siblingsOfType)", color: typeColor)
                statBadge(label: "TOTAL ACTIVE", value: "\(totalActive)", color: C.listen)
                Spacer()
            }

            Text(item.content)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(C.surfaceHi)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(C.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func statBadge(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08), in: Capsule())
    }
}

// MARK: - Panel: Memory Bank

private struct DirectiveCreateForm: View {
    @Binding var type: String
    @Binding var title: String
    @Binding var content: String
    @Binding var target: String
    @Binding var priority: Int
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("", selection: $type) {
                    ForEach(["directive", "protocol", "rule"], id: \.self) { Text($0.uppercased()).font(.system(size: 9, design: .monospaced)).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
                Text("PRIORITY").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5).foregroundColor(.secondary)
                Stepper(value: $priority, in: 0...10) { Text("\(priority)").font(.system(size: 11, design: .monospaced)).foregroundColor(.primary.opacity(0.85)) }
                    .frame(width: 90)
                Spacer()
            }
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(C.surfaceHi)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            TextField("Target (e.g. all, eve, agents)", text: $target)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .background(C.surfaceHi)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            TextEditor(text: $content)
                .scrollContentBackground(.hidden)
                .font(.system(size: 11))
                .frame(minHeight: 70, maxHeight: 120)
                .padding(6)
                .background(C.surfaceHi)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("SAVE DIRECTIVE", action: onSave)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(C.eve)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(C.eve.opacity(0.12))
                    .overlay(Capsule().strokeBorder(C.eve.opacity(0.5), lineWidth: 1))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .disabled(title.isEmpty || content.isEmpty)
            }
        }
    }
}

struct MemoryPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void
    @State private var filter: String = "all"  // all | fact | task | objective | preference
    @State private var search: String = ""
    @State private var showCreate = false
    @State private var newType = "fact"
    @State private var newContent = ""
    @State private var newPriority = 5

    private var filtered: [MemoryItem] {
        var rows = store.memories
        if filter != "all" { rows = rows.filter { $0.type == filter } }
        if !search.isEmpty {
            let q = search.lowercased()
            rows = rows.filter { $0.content.lowercased().contains(q) }
        }
        return rows.sorted { $0.priority > $1.priority }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "MEMORY BANK", subtitle: "\(store.memories.count) ENTRIES", onDismiss: onDismiss)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.58))
                    TextField("Search memory…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                }
                .padding(10)
                .background(C.surfaceHi)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(C.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 6) {
                    ForEach(["all", "fact", "task", "objective", "preference"], id: \.self) { f in
                        Button(action: { filter = f }) {
                            Text(f.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(filter == f ? .white : .secondary.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(filter == f ? C.listen.opacity(0.22) : C.surfaceHi)
                                .overlay(Capsule().strokeBorder(filter == f ? C.listen.opacity(0.45) : C.hairline, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button(action: { withAnimation { showCreate.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCreate ? "minus" : "plus").font(.system(size: 9, weight: .bold))
                            Text(showCreate ? "CLOSE" : "NEW").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                        }
                        .foregroundColor(C.listen)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(C.listen.opacity(0.12))
                        .overlay(Capsule().strokeBorder(C.listen.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            if showCreate {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Picker("", selection: $newType) {
                            ForEach(["fact", "task", "objective", "preference"], id: \.self) { Text($0.uppercased()).font(.system(size: 9, design: .monospaced)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 130)
                        Text("PRIORITY").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5).foregroundColor(.secondary)
                        Stepper(value: $newPriority, in: 0...10) { Text("\(newPriority)").font(.system(size: 11, design: .monospaced)).foregroundColor(.primary.opacity(0.85)) }
                            .frame(width: 90)
                        Spacer()
                    }
                    TextEditor(text: $newContent)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 11))
                        .frame(minHeight: 60, maxHeight: 100)
                        .padding(6)
                        .background(C.surfaceHi)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Spacer()
                        Button("SAVE MEMORY") {
                            guard !newContent.isEmpty else { return }
                            Task { await store.createMemory(type: newType, content: newContent, priority: newPriority) }
                            newContent = ""; newType = "fact"; newPriority = 5
                            withAnimation { showCreate = false }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(C.listen)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(C.listen.opacity(0.12))
                        .overlay(Capsule().strokeBorder(C.listen.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .disabled(newContent.isEmpty)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered) { m in
                        MemoryRow(item: m, onDelete: { Task { await store.deleteMemory(m) } })
                    }
                    if filtered.isEmpty {
                        EmptyInspectorState(
                            title: search.isEmpty ? "No memories of type \(filter)" : "No matches for \(search)",
                            detail: "Eve auto-summarizes conversations into the memory bank every 20 messages."
                        )
                        .padding(.top, 30)
                    }
                }
                .padding(14)
            }
        }
        .task { await store.fetchMemories() }
    }
}

private struct MemoryRow: View {
    let item: MemoryItem
    let onDelete: () -> Void

    private var typeColor: Color {
        switch item.type {
        case "objective":  return C.eve
        case "task":       return C.think
        case "preference": return C.listen
        default:           return .secondary.opacity(0.4)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.type.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(typeColor)
                Text("P\(item.priority)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.58))
            }
            .frame(width: 64, alignment: .leading)

            Text(item.content)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.58))
                    .frame(width: 28, height: 28)
                    .background(C.surfaceHi)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Panel: Chats

struct ChatsPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void
    @State private var selectedConversationId: String? = nil
    @Environment(\.openWindow) private var openWindow

    // Cross-thread search across all conversations + message content
    @State private var searchText: String = ""
    @State private var searchResults: [CrossThreadSearchHit] = []
    @State private var searching: Bool = false

    /// Debounce token — only the last query's task should mutate state.
    @State private var searchTaskId: UUID = UUID()

    private func runSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            searching = false
            return
        }
        let myId = UUID()
        searchTaskId = myId
        searching = true
        Task {
            // Debounce ~250ms
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard searchTaskId == myId else { return }
            let results = await store.crossThreadSearch(query: trimmed)
            await MainActor.run {
                guard searchTaskId == myId else { return }
                searchResults = results
                searching = false
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let splitLayout = proxy.size.width > 860

            VStack(spacing: 0) {
                SheetHeader(title: "CONVERSATIONS", subtitle: "\(store.conversations.count) THREADS", onDismiss: onDismiss)

                // Search bar — searches titles + all message content
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundColor(C.listen)
                    TextField("Search every thread… (titles + content)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onChange(of: searchText) { _, q in runSearch(q) }
                        .onSubmit { runSearch(searchText) }
                    if searching {
                        ProgressView().controlSize(.mini).tint(C.listen)
                    }
                    if !searchText.isEmpty {
                        Button(action: { searchText = ""; searchResults = [] }) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(C.surfaceHi.opacity(0.65))
                )
                .padding(.horizontal, 12)
                .padding(.top, 6)

                // Search results — when query yields hits, swap them in for
                // the regular conversation list.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !searchResults.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(searchResults) { hit in
                                    Button {
                                        Task {
                                            await store.loadConversation(id: hit.conversationId, title: hit.title)
                                            onDismiss()
                                        }
                                    } label: {
                                        SearchHitRow(hit: hit, query: searchText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text("\(searchResults.count) THREAD\(searchResults.count == 1 ? "" : "S") MATCH \"\(searchText)\"")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 14)
                            }
                        }
                    } else if !searching {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No threads match \"\(searchText)\"")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        Spacer()
                    }
                } else {

                Button {
                    store.newConversation()
                    onDismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("NEW CONVERSATION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(C.eve)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [C.eve.opacity(0.11), C.eve.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if splitLayout {
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(store.conversations) { conv in
                                    ChatRow2(conv: conv, isSelected: (selectedConversationId ?? store.conversations.first?.id) == conv.id)
                                        .onTapGesture { selectedConversationId = conv.id }
                                        .contextMenu {
                                            Button("Open in New Window") { openWindow(id: "conversation-detail", value: conv.id) }
                                            Button("Load in Main Chat") {
                                                Task {
                                                    await store.loadConversation(id: conv.id, title: conv.title)
                                                    onDismiss()
                                                }
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 14)
                        }
                        .frame(width: 360)
                        .padding(.trailing, 8)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let selected = selectedConversation {
                                    DetailMetric(title: "SOURCE", value: selected.source.uppercased(), accent: selected.source == "lumen" ? C.eve : C.listen)
                                    DetailMetric(title: "UPDATED", value: selected.updatedAt.lumenRelative, accent: .primary)
                                    DetailSection(title: "TITLE", text: selected.title)
                                    HStack(spacing: 10) {
                                        PanelActionButton(label: "OPEN AS WINDOW", color: C.eve, disabled: false) {
                                            openWindow(id: "conversation-detail", value: selected.id)
                                        }
                                        PanelActionButton(label: "LOAD IN MAIN", color: C.listen, disabled: false) {
                                            Task {
                                                await store.loadConversation(id: selected.id, title: selected.title)
                                                onDismiss()
                                            }
                                        }
                                        PanelActionButton(label: "NEW THREAD", color: .secondary.opacity(0.5), disabled: false) {
                                            store.newConversation()
                                            onDismiss()
                                        }
                                    }
                                } else {
                                    EmptyInspectorState(title: "No conversations loaded", detail: "Conversation history will appear here after sync.")
                                }
                            }
                            .padding(22)
                        }
                        .padding(.leading, 8)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.conversations) { conv in
                                ChatRow2(conv: conv, isSelected: false)
                                    .onTapGesture {
                                        Task {
                                            await store.loadConversation(id: conv.id, title: conv.title)
                                            onDismiss()
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                    }
                }
                }  // close `else` from search-active branch
            }
        }
        .task { await store.fetchConversations() }
        .onAppear {
            if selectedConversationId == nil {
                selectedConversationId = store.conversations.first?.id
            }
        }
    }

    private var selectedConversation: ConversationSummary? {
        if let selectedConversationId {
            return store.conversations.first(where: { $0.id == selectedConversationId })
        }
        return store.conversations.first
    }
}

/// Row for cross-thread search results. Highlights the matched substring
/// inline in the snippet so the Director sees WHY a thread was returned.
private struct SearchHitRow: View {
    let hit: CrossThreadSearchHit
    let query: String

    private var matchAccent: Color {
        switch hit.matchType {
        case "title":   return C.eve
        case "both":    return C.eve
        default:        return C.listen
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(matchAccent).frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(hit.title.isEmpty ? "Untitled" : hit.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(hit.matchType.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                        .foregroundColor(matchAccent)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(matchAccent.opacity(0.13))
                        .clipShape(Capsule())
                }
                if !hit.snippet.isEmpty {
                    Text(highlight(hit.snippet, query: query))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(hit.source.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func highlight(_ text: String, query: String) -> AttributedString {
        var out = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return out }
        // Mark each occurrence of q in the snippet with a yellow background
        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.length > 0 {
            let r = nsText.range(of: q, options: [.caseInsensitive], range: searchRange)
            if r.location == NSNotFound { break }
            if let attrRange = Range(r, in: text), let aRange = out.range(of: text[attrRange]) {
                out[aRange].foregroundColor = matchAccent
                out[aRange].font = .system(size: 11, weight: .semibold)
            }
            searchRange.location = r.location + r.length
            searchRange.length = nsText.length - searchRange.location
        }
        return out
    }
}

struct FilesPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void

    @State private var rootURL: URL?
    @State private var scopedURL: URL?
    @State private var entries: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewText = ""
    @State private var statusText = "Choose a file or folder to inspect local content."

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "LOCAL FILE ACCESS", subtitle: rootURL?.path ?? "NO LOCATION SELECTED", onDismiss: onDismiss)

            HStack(spacing: 10) {
                PanelActionButton(label: "OPEN FOLDER", color: C.listen, disabled: false) {
                    chooseLocation(allowsDirectories: true)
                }
                PanelActionButton(label: "OPEN FILE", color: C.eve, disabled: false) {
                    chooseLocation(allowsDirectories: false)
                }
                PanelActionButton(label: "EVALUATE WITH EVE", color: C.think, disabled: selectedURL == nil || previewText.isEmpty) {
                    evaluateSelectedFile()
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)

            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(entries, id: \.path) { entry in
                            FileEntryRow(url: entry, isSelected: entry == selectedURL)
                                .contentShape(Rectangle())
                                .onTapGesture { loadPreview(for: entry) }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .frame(width: 320)
                .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1), alignment: .trailing)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSection(title: "STATUS", text: statusText)

                        if let selectedURL {
                            DetailSection(title: "PATH", text: selectedURL.path)
                            DetailSection(title: "TYPE", text: selectedURL.hasDirectoryPath ? "Directory" : "File")
                        }

                        if !previewText.isEmpty {
                            DetailSection(title: "PREVIEW", text: previewText)
                        }
                    }
                    .padding(22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { restoreLastBookmarkIfAvailable() }
        .onDisappear { releaseScope() }
    }

    private func chooseLocation(allowsDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = allowsDirectories
        panel.canChooseFiles = !allowsDirectories
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        adoptScope(for: url)
        FileBookmarkStore.save(url: url)
        rootURL = url
        if url.hasDirectoryPath {
            loadDirectory(url)
        } else {
            entries = [url]
            loadPreview(for: url)
        }
    }

    private func adoptScope(for url: URL) {
        releaseScope()
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        } else {
            scopedURL = nil
        }
    }

    private func releaseScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func loadDirectory(_ url: URL) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        entries = items.sorted { lhs, rhs in
            let leftIsDir = (try? lhs.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            let rightIsDir = (try? rhs.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            if leftIsDir != rightIsDir { return leftIsDir && !rightIsDir }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        selectedURL = nil
        previewText = ""
        statusText = "Loaded \(entries.count) items from \(url.lastPathComponent)."
    }

    private func loadPreview(for url: URL) {
        selectedURL = url

        if url.hasDirectoryPath {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
            previewText = ""
            statusText = "\(url.lastPathComponent) contains \(count) items."
            return
        }

        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) < 256_000 else {
            previewText = ""
            statusText = "Preview unavailable. File is too large for inline inspection."
            return
        }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            previewText = String(text.prefix(20_000))
            statusText = "Preview loaded for \(url.lastPathComponent)."
        } else {
            previewText = ""
            statusText = "Preview unavailable. This file is not UTF-8 text."
        }
    }

    private func evaluateSelectedFile() {
        guard let selectedURL, !selectedURL.hasDirectoryPath, !previewText.isEmpty else { return }
        let payload = """
        Evaluate this local file for me.

        Path: \(selectedURL.path)

        Content:
        \(previewText)
        """

        Task {
            await store.send(payload)
            await MainActor.run { onDismiss() }
        }
    }

    private func restoreLastBookmarkIfAvailable() {
        guard rootURL == nil, let url = FileBookmarkStore.restore() else { return }
        adoptScope(for: url)
        rootURL = url
        if url.hasDirectoryPath {
            loadDirectory(url)
        } else {
            entries = [url]
            loadPreview(for: url)
        }
    }
}

struct SystemPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void

    private var supportDirectory: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lumen", isDirectory: true)
            .path ?? "Unavailable"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "SYSTEM ACCESS", subtitle: "ENDPOINTS • DATASETS • CACHE", onDismiss: onDismiss)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DetailMetric(title: "AGENTS", value: "\(store.agents.count)", accent: C.listen)
                        DetailMetric(title: "OPERATIONS", value: "\(store.operations.count)", accent: C.think)
                        DetailMetric(title: "CONVERSATIONS", value: "\(store.conversations.count)", accent: C.eve)
                        DetailMetric(title: "SESSION", value: LumenAPIManager.shared.sessionCookie == nil ? "LOCKED" : "ACTIVE", accent: LumenAPIManager.shared.sessionCookie == nil ? C.danger : C.listen)
                    }

                    DetailSection(title: "NEXUS BASE", text: LumenAPIManager.shared.nexusBase)
                    BrainModeToggle(store: store)
                    ModelPickerSection()
                    VoicePickerSection()
                    DetailSection(title: "SUPABASE CACHE", text: supportDirectory + "/session_cache.json")
                    DetailSection(title: "LOCAL MEMORY FILES", text: supportDirectory + "/eve-base.md\n" + supportDirectory + "/eve-private.md")
                    DetailSection(title: "ACTIVE CONVERSATION", text: store.currentConversationId ?? "No active thread")
                    ForEach(store.dashboardRecords.keys.sorted(), id: \.self) { section in
                        KeyValueSection(title: section.uppercased(), values: store.dashboardRecords[section] ?? [:])
                    }
                }
                .padding(22)
            }
        }
        .task { await store.fetchConversations() }
    }
}

struct SettingsPanel: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "ACCOUNT SETTINGS", subtitle: auth.isAuthenticated ? "AUTHENTICATED" : "LOCKED", onDismiss: onDismiss)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DetailMetric(title: "AUTH STATE", value: auth.isAuthenticated ? "SIGNED IN" : "SIGNED OUT", accent: auth.isAuthenticated ? C.listen : C.danger)
                        DetailMetric(title: "BASE", value: LumenAPIManager.shared.nexusBase, accent: C.eve)
                    }

                    DetailSection(title: "SESSION TOKEN", text: maskedCookie)
                    DetailSection(title: "CURRENT CONVERSATION", text: store.currentConversationId ?? "No active conversation")

                    HStack(spacing: 10) {
                        PanelActionButton(label: "NEW THREAD", color: C.eve, disabled: false) {
                            store.clearHistory()
                            store.newConversation()
                        }
                        PanelActionButton(label: "REFRESH DASHBOARD", color: C.listen, disabled: false) {
                            Task { await store.fetchDashboard() }
                        }
                        PanelActionButton(label: "SIGN OUT", color: C.danger, disabled: false) {
                            auth.signOut()
                            onDismiss()
                        }
                    }
                }
                .padding(22)
            }
        }
    }

    private var maskedCookie: String {
        guard let cookie = LumenAPIManager.shared.sessionCookie, !cookie.isEmpty else { return "No active session cookie" }
        let prefix = cookie.prefix(10)
        let suffix = cookie.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}

private struct ChatRow2: View {
    let conv: ConversationSummary
    let isSelected: Bool
    @State private var hovered = false

    private var sourceColor: Color {
        conv.source == "lumen" ? C.eve : C.listen
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(sourceColor).frame(width: 5, height: 5)
                .shadow(color: sourceColor, radius: 3)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conv.title.isEmpty ? "Untitled" : conv.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    if conv.messageCount > 0 {
                        Text("\(conv.messageCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if !conv.preview.isEmpty {
                    Text(conv.preview)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text(conv.source.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(sourceColor)
                    Text("·")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(conv.updatedAt.lumenRelative)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .softRowSurface(isSelected: isSelected, isHovered: hovered, accent: sourceColor)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct FileEntryRow: View {
    let url: URL
    let isSelected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 12))
                .foregroundColor(url.hasDirectoryPath ? C.listen : C.eve)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.84))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(url.hasDirectoryPath ? "Directory" : "File")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .softRowSurface(isSelected: isSelected, isHovered: hovered, accent: url.hasDirectoryPath ? C.listen : C.eve)
        .onHover { hovered = $0 }
    }
}

private struct EmptyInspectorState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.88))
            Text(detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct KeyValueSection: View {
    let title: String
    let values: [String: String]

    private var rows: [(String, String)] {
        values
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)

            if rows.isEmpty {
                Text("No fields available")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows, id: \.0) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(value)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.64))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum FileBookmarkStore {
    private static let key = "lumen.files.bookmark"

    static func save(url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale {
            save(url: url)
        }
        return url
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(accent.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BrainModeToggle: View {
    @ObservedObject var store: LumenStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BRAIN MODE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(2)
                Spacer()
                Text(store.preferLocalBrain ? "LOCAL FIRST" : "CLOUD FIRST")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(store.preferLocalBrain ? C.listen : C.eve)
                    .tracking(1.5)
            }

            HStack(spacing: 8) {
                BrainOption(
                    icon: "cloud.fill",
                    label: "Cloud",
                    sub: "Grok + tools",
                    selected: !store.preferLocalBrain,
                    accent: C.eve
                ) { store.preferLocalBrain = false }

                BrainOption(
                    icon: "cpu",
                    label: "Local",
                    sub: "Ollama, offline",
                    selected: store.preferLocalBrain,
                    accent: C.listen
                ) { store.preferLocalBrain = true }
            }

            Text(store.preferLocalBrain
                 ? "Eve answers from local Ollama. Falls back to nexus-web Grok if Ollama is down."
                 : "Eve answers from nexus-web Grok with full tool calling. Falls back to local Ollama if offline.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary.opacity(0.58))
                .lineLimit(2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BrainOption: View {
    let icon: String
    let label: String
    let sub: String
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(selected ? accent : .secondary.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background((selected ? accent : Color.primary).opacity(selected ? 0.15 : 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selected ? .secondary.opacity(0.95) : .secondary.opacity(0.6))
                    Text(sub)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.6))
                }
                Spacer()
                if selected {
                    Circle().fill(accent).frame(width: 6, height: 6).shadow(color: accent, radius: 3)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? accent.opacity(0.08) : C.surfaceHi)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? accent.opacity(0.4) : C.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct VoicePickerSection: View {
    @State private var active: String = LumenAPIManager.shared.voiceId

    private struct VoiceOption: Identifiable {
        let id: String
        let name: String
        let description: String
    }

    private let options: [VoiceOption] = [
        VoiceOption(id: "EXAVITQu4vr4xnSDxMaL", name: "Bella",   description: "Warm female · default"),
        VoiceOption(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel",  description: "Calm female · narrator"),
        VoiceOption(id: "AZnzlk1XvdvUeBnXmlld", name: "Domi",    description: "Confident female"),
        VoiceOption(id: "MF3mGyEYCl7XYWbV9V6O", name: "Elli",    description: "Young female · friendly"),
        VoiceOption(id: "ErXwobaYiN019PkySvjV", name: "Antoni",  description: "Smooth male"),
        VoiceOption(id: "pNInz6obpgDQGcFmaJgB", name: "Adam",    description: "Deep male · gravitas"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EVE VOICE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(2)
                Spacer()
                Text("ELEVENLABS")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(1.5)
            }

            VStack(spacing: 4) {
                ForEach(options) { v in
                    Button(action: { select(v.id) }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(v.id == active ? C.eve : C.surfaceHi)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(v.id == active ? .secondary.opacity(0.9) : .secondary.opacity(0.6))
                                Text(v.description)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.58))
                            }
                            Spacer()
                            if v.id == active {
                                Text("ACTIVE")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundColor(C.eve)
                                    .tracking(1.5)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(v.id == active ? C.eve.opacity(0.08) : C.surfaceHi)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(v.id == active ? C.eve.opacity(0.4) : C.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func select(_ id: String) {
        LumenAPIManager.shared.setVoiceId(id)
        active = id
    }
}

private struct ModelPickerSection: View {
    @State private var models: [String] = []
    @State private var active: String = LumenAPIManager.shared.localModel
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOCAL LLM")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(2)
                Spacer()
                Text("OLLAMA · :11434")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(1.5)
            }

            if loading {
                Text("Scanning installed models…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.6))
            } else if models.isEmpty {
                Text("No models found. Run `ollama pull <name>` from terminal.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(models, id: \.self) { name in
                        Button(action: { select(name) }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(name == active ? C.listen : C.surfaceHi)
                                    .frame(width: 6, height: 6)
                                Text(name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(name == active ? .secondary.opacity(0.85) : .secondary.opacity(0.55))
                                Spacer()
                                if name == active {
                                    Text("ACTIVE")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(C.listen)
                                        .tracking(1.5)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(name == active ? C.listen.opacity(0.08) : C.surfaceHi)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(name == active ? C.listen.opacity(0.4) : C.hairline, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task { await refresh() }
    }

    private func select(_ name: String) {
        LumenAPIManager.shared.setLocalModel(name)
        active = name
    }

    private func refresh() async {
        let list = await LumenAPIManager.shared.listLocalModels()
        models = list
        active = LumenAPIManager.shared.localModel
        loading = false
    }
}

// MARK: - Sheet header

struct SheetHeader: View {
    let title: String
    let subtitle: String
    let onDismiss: () -> Void
    var onPopOut: (() -> Void)? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.75))
                    .tracking(2)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            Spacer()
            if let onPopOut {
                Button(action: onPopOut) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(C.surfaceHi)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open in new window")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.58))
                    .frame(width: 26, height: 26)
                    .background(C.surfaceHi)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }
}


// MARK: - Command Palette (⌘K)

struct CommandPaletteOverlay: View {
    @Binding var activePanel: MainView.PanelType
    @EnvironmentObject var store: LumenStore
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    enum ResultKind {
        case agent, operation, directive, memory, conversation, panel
    }

    struct Result: Identifiable {
        let id: String
        let kind: ResultKind
        let title: String
        let subtitle: String
        let action: () -> Void
    }

    private var allResults: [Result] {
        var out: [Result] = []
        // Panel jumps
        out.append(Result(id: "panel-agents",     kind: .panel, title: "Agents",     subtitle: "Open panel · ⌘⌥1") { activePanel = .agents })
        out.append(Result(id: "panel-ops",        kind: .panel, title: "Operations", subtitle: "Open panel · ⌘⌥2") { activePanel = .operations })
        out.append(Result(id: "panel-directives", kind: .panel, title: "Directives", subtitle: "Open panel · ⌘⌥3") { activePanel = .directives })
        out.append(Result(id: "panel-memory",     kind: .panel, title: "Memory Bank", subtitle: "Open panel · ⌘⌥4") { activePanel = .memory })
        out.append(Result(id: "panel-chats",      kind: .panel, title: "Conversations", subtitle: "Open panel · ⌘⌥5") { activePanel = .chats })

        // Agents
        for a in store.agents {
            out.append(Result(id: "a-\(a.agentId)", kind: .agent, title: a.name, subtitle: "\(a.role) · \(a.status.uppercased())") {
                activePanel = .agents
            })
        }
        // Operations
        for o in store.operations {
            out.append(Result(id: "o-\(o.operationId)", kind: .operation, title: o.name, subtitle: "\(o.status.uppercased()) · \(o.priority.uppercased())") {
                activePanel = .operations
            })
        }
        // Directives
        for d in store.directives {
            out.append(Result(id: "d-\(d.id)", kind: .directive, title: d.title, subtitle: "\(d.type.uppercased()) · P\(d.priority)") {
                activePanel = .directives
            })
        }
        // Memory
        for m in store.memories {
            let snippet = String(m.content.prefix(60))
            out.append(Result(id: "m-\(m.id)", kind: .memory, title: snippet, subtitle: "\(m.type.uppercased()) · P\(m.priority)") {
                activePanel = .memory
            })
        }
        // Conversations
        for c in store.conversations {
            out.append(Result(id: "c-\(c.id)", kind: .conversation, title: c.title, subtitle: "Conversation · \(c.source)") {
                activePanel = .chats
            })
        }
        return out
    }

    private var filtered: [Result] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return Array(allResults.prefix(40)) }
        return allResults.filter { r in
            r.title.lowercased().contains(q) || r.subtitle.lowercased().contains(q)
        }.prefix(40).map { $0 }
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    TextField("Jump to anything…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundColor(.primary.opacity(0.95))
                        .focused($fieldFocused)
                        .onSubmit { activate() }
                    Text("ESC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.primary.opacity(0.58))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(C.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { dismiss() }
                }
                .padding(16)
                .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)

                // Results
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, r in
                            ResultRow(result: r, isSelected: idx == selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = idx
                                    activate()
                                }
                                .onHover { hovering in
                                    if hovering { selectedIndex = idx }
                                }
                        }
                        if filtered.isEmpty {
                            Text("No matches.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.6))
                                .padding(.vertical, 30)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 380)
            }
            .frame(width: 620)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(C.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(C.hairline, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 40, y: 18)
            .onKeyPress(.escape) { dismiss(); return .handled }
            .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
            .onKeyPress(.downArrow) { selectedIndex = min(filtered.count - 1, selectedIndex + 1); return .handled }
        }
        .onAppear { fieldFocused = true; selectedIndex = 0 }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private func activate() {
        guard selectedIndex < filtered.count else { return }
        filtered[selectedIndex].action()
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            store.commandPaletteVisible = false
            query = ""
        }
    }
}

private struct ResultRow: View {
    let result: CommandPaletteOverlay.Result
    let isSelected: Bool

    private var iconName: String {
        switch result.kind {
        case .agent:        return "person.3.fill"
        case .operation:    return "bolt.fill"
        case .directive:    return "shield.lefthalf.filled"
        case .memory:       return "brain.head.profile"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .panel:        return "rectangle.stack.fill"
        }
    }

    private var iconColor: Color {
        switch result.kind {
        case .agent:        return C.listen
        case .operation:    return C.think
        case .directive:    return C.eve
        case .memory:       return C.listen
        case .conversation: return C.eve
        case .panel:        return .secondary.opacity(0.5)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(isSelected ? Color.secondary.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Menu bar popover

struct MenuBarPopover: View {
    @EnvironmentObject var store: LumenStore
    @EnvironmentObject var auth: AuthManager
    @Environment(\.openWindow) private var openWindow

    private var lastEve: ChatMessage? {
        store.messages.last { $0.role == .assistant }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(store.eveStatus.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: store.eveStatus.color, radius: 4)
                Text("EVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
                Text(store.eveStatus.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.secondary)
            }

            Divider()

            if !auth.isAuthenticated {
                Text("Locked. Open Lumen to authenticate.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else if let last = lastEve {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST REPLY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.primary.opacity(0.6))
                    Text(last.content)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
            } else {
                Text("No conversation yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Quick stats
            HStack(spacing: 14) {
                MenuStat(label: "AGENTS", value: "\(store.agents.count)")
                MenuStat(label: "OPS",    value: "\(store.operations.count)")
                MenuStat(label: "MEM",    value: "\(store.memories.count)")
                MenuStat(label: "DIR",    value: "\(store.directives.count)")
            }

            Divider()

            // Actions
            VStack(spacing: 4) {
                MenuRowButton(label: "Open Lumen", icon: "macwindow") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuRowButton(label: "New Conversation", icon: "plus.bubble") {
                    store.newConversation()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuRowButton(label: "Agents", icon: "person.3.fill") {
                    openWindow(id: "panel", value: MainView.PanelType.agents)
                }
                MenuRowButton(label: "Operations", icon: "bolt.fill") {
                    openWindow(id: "panel", value: MainView.PanelType.operations)
                }
                MenuRowButton(label: "Memory Bank", icon: "brain.head.profile") {
                    openWindow(id: "panel", value: MainView.PanelType.memory)
                }
                MenuRowButton(label: "Directives", icon: "shield.lefthalf.filled") {
                    openWindow(id: "panel", value: MainView.PanelType.directives)
                }
            }

            Divider()

            HStack {
                Button("Quit Lumen") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(LumenAPIManager.shared.localModel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.58))
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(C.surface)
    }
}

private struct MenuStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.primary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MenuRowButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(hovered ? Color.secondary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Detached panel window

struct DetachedPanelWindow: View {
    let type: MainView.PanelType
    @EnvironmentObject var store: LumenStore
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            BackgroundLayer()
            VStack(spacing: 0) {
                detachedHeader
                content
            }
        }
        // Follows system appearance via adaptive palette (see C palette).
    }

    private var detachedHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: typeIcon)
                .font(.system(size: 11))
                .foregroundColor(typeColor)
            Text(type.title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.7))
                .tracking(3)
            Spacer()
            Text("DETACHED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(C.surfaceHi)
        .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        switch type {
        case .none:       Text("No panel selected").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .agents:     AgentPanel(store: store, onDismiss: closeWindow)
        case .operations: OpsPanel2(store: store, onDismiss: closeWindow)
        case .directives: DirectivesPanel(store: store, onDismiss: closeWindow)
        case .memory:     MemoryPanel(store: store, onDismiss: closeWindow)
        case .chats:      ChatsPanel(store: store, onDismiss: closeWindow)
        case .nexusMap:   NexusMapView(store: store)
        case .files:      FilesPanel(store: store, onDismiss: closeWindow)
        case .code:       CodePanel(store: store, onClose: closeWindow)
        case .system:     SystemPanel(store: store, onDismiss: closeWindow)
        case .settings:   SettingsPanel(store: store, auth: auth, onDismiss: closeWindow)
        }
    }

    private func closeWindow() {
        dismissWindow(id: "panel", value: type)
    }

    private var typeIcon: String {
        switch type {
        case .agents:     return "person.3.fill"
        case .operations: return "bolt.fill"
        case .directives: return "shield.lefthalf.filled"
        case .memory:     return "brain.head.profile"
        case .chats:      return "bubble.left.and.bubble.right.fill"
        case .nexusMap:   return "globe"
        case .files:      return "folder.fill"
        case .code:       return "terminal.fill"
        case .system:     return "cpu.fill"
        case .settings:   return "gearshape.fill"
        case .none:       return "questionmark"
        }
    }

    private var typeColor: Color {
        switch type {
        case .agents:     return C.listen
        case .operations: return C.think
        case .directives: return C.eve
        case .memory:     return C.listen
        case .chats:      return C.eve
        case .nexusMap:   return C.eve
        case .files:      return C.eve
        case .system:     return C.listen
        case .settings:   return C.think
        default:          return .white
        }
    }
}

struct OperationWindow: View {
    let operationId: String
    @EnvironmentObject var store: LumenStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var updating = false

    private var operation: OperationItem? {
        store.operations.first { $0.operationId == operationId }
    }

    var body: some View {
        ZStack {
            BackgroundLayer()

            if let operation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: operation)

                        OpsDetailCard(
                            op: operation,
                            details: store.operationRecords[operation.operationId] ?? [:],
                            records: store.recordsByOp[operation.operationId] ?? [],
                            briefs: store.briefsByOp[operation.operationId] ?? [:],
                            generatingBrief: store.briefGenerating,
                            isUpdating: updating,
                            onSetStatus: { update(operation: operation, status: $0) },
                            onAddRecord: { title, content, type in
                                Task { await store.addRecord(opId: operation.operationId, title: title, content: content, type: type) }
                            },
                            onRegenerateBrief: { kind in
                                Task { await store.regenerateBrief(opId: operation.operationId, kind: kind) }
                            }
                        )
                    }
                    .padding(24)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Operation unavailable")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.88))
                    Text("The requested operation is not loaded in the current operations dataset.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    PanelActionButton(label: "CLOSE WINDOW", color: C.eve, disabled: false) {
                        dismissWindow(id: "operation-detail", value: operationId)
                    }
                    .frame(maxWidth: 220)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
        }
        // Follows system appearance via adaptive palette (see C palette).
        .task(id: operationId) {
            await store.fetchOperations()
            await store.fetchRecords(opId: operationId)
            await store.fetchBriefs(opId: operationId)
        }
    }

    @ViewBuilder
    private func header(for operation: OperationItem) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(operation.name)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.92))
                Text("\(operation.codename) · \(operation.operationId)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            PanelActionButton(label: "CLOSE WINDOW", color: .secondary.opacity(0.65), disabled: false) {
                dismissWindow(id: "operation-detail", value: operationId)
            }
            .frame(width: 180)
        }
    }

    private func update(operation: OperationItem, status: String) {
        updating = true
        Task {
            await LumenAPIManager.shared.setOpStatus(id: operation.operationId, status: status)
            await store.fetchOperations()
            await store.fetchRecords(opId: operation.operationId)
            await store.fetchBriefs(opId: operation.operationId)
            updating = false
        }
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let audioLevel: Float
    let color: Color
    private let count = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2, height: barHeight(i))
                    .animation(.easeOut(duration: 0.07).delay(Double(i) * 0.008), value: audioLevel)
            }
        }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let center  = Double(count) / 2
        let dist    = abs(Double(i) - center) / center
        let shape   = 1.0 - dist * 0.4
        let level   = CGFloat(audioLevel)
        return 2 + (14 - 2) * level * CGFloat(shape)
    }
}

// MARK: - Clock

struct TimeDisplay: View {
    @State private var time = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(time, format: .dateTime.hour().minute().second())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary.opacity(0.58))
            Text(time, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .onReceive(timer) { time = $0 }
    }
}

// MARK: - Date extension

private extension Date {
    var lumenRelative: String {
        let s = -timeIntervalSinceNow
        if s < 60        { return "JUST NOW" }
        if s < 3600      { return "\(Int(s/60))M AGO" }
        if s < 86400     { return "\(Int(s/3600))H AGO" }
        if s < 86400 * 7 { return "\(Int(s/86400))D AGO" }
        let df = DateFormatter(); df.dateFormat = "MMM d"
        return df.string(from: self).uppercased()
    }
}
