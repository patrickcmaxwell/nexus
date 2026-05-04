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
        app.isDark ? NSColor(red: 0.085, green: 0.09,  blue: 0.14,  alpha: 1)
                   : NSColor(red: 0.94,  green: 0.94,  blue: 0.97,  alpha: 1)
    })
    static let hairline = Color(nsColor: NSColor(name: "lumen.hairline") { app in
        app.isDark ? NSColor(white: 1.0, alpha: 0.10)
                   : NSColor(white: 0.0, alpha: 0.10)
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
        case none, agents, operations, directives, memory, chats, nexusMap = "nexus_map", files, system, settings
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
        NavigationSplitView {
            SidebarNav(
                store: store,
                auth: auth,
                lmStatus: lmStatus,
                activePanel: $activePanel
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 300)
        } detail: {
            DetailContainer(
                activePanel: $activePanel,
                store: store,
                auth: auth,
                lmStatus: lmStatus,
                inputText: $inputText,
                inputFocused: $inputFocused,
                onSubmit: submitInput
            )
        }
        .navigationSplitViewStyle(.balanced)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activePanel)
        .task {
            await store.fetchDashboard()
            await store.fetchOperations()
            await pingLMStudio()
        }
    }

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await store.send(text) }
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
}

// MARK: - Sidebar (native vibrancy, single column of section-grouped items)

struct SidebarNav: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus
    @Binding var activePanel: MainView.PanelType
    @EnvironmentObject var sync: LumenSync
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
    private func row(_ panel: MainView.PanelType, label: String, icon: String, tint: Color, badge: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
            Spacer()
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
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
                LiveThreadView(
                    store: store,
                    inputText: $inputText,
                    inputFocused: $inputFocused,
                    onSubmit: onSubmit
                )
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
            case .system:
                SystemPanel(store: store) { activePanel = .none }
            case .settings:
                SettingsPanel(store: store, auth: auth) { activePanel = .none }
            }
        }
        .navigationTitle(activePanel.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EveStatusToolbar(store: store)
            }
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
            Divider()
            ComposerBar(
                text: $inputText,
                inputFocused: $inputFocused,
                store: store,
                onSubmit: onSubmit
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Composer bar (inline, dock at bottom of conversation pane)

struct ComposerBar: View {
    @Binding var text: String
    @FocusState.Binding var inputFocused: Bool
    @ObservedObject var store: LumenStore
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !store.pendingImages.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(C.think)
                    Text("\(store.pendingImages.count) image\(store.pendingImages.count == 1 ? "" : "s") attached")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { store.clearPendingImages() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
            }

            HStack(spacing: 10) {
                Button(action: toggleMic) {
                    let active = store.fluidListening || store.eveStatus == .listening
                    Image(systemName: active ? "mic.fill" : "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(active ? C.listen : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.fluidListening ? "Stop listening" : "Start listening")

                Button(action: pickImage) {
                    Image(systemName: store.pendingImages.isEmpty ? "photo" : "photo.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(store.pendingImages.isEmpty ? Color.secondary : C.think)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach image")

                TextField("Send a directive…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit { onSubmit() }
                    .font(.system(size: 14))

                if store.eveStatus == .speaking {
                    Button(action: { store.voice.stopSpeaking(); store.eveStatus = .idle }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(C.danger, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop speaking")
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: onSubmit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(C.eve, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .background(.bar)
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

    private var displayMessages: [ChatMessage] { store.messages }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if displayMessages.isEmpty {
                            EmptyState()
                                .padding(.top, 80)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(displayMessages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
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
                    .padding(.vertical, 18)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: displayMessages.count)
                    .animation(.easeInOut(duration: 0.2), value: store.eveStatus)
                }
                .onChange(of: displayMessages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                }
                .onChange(of: store.eveStatus) { _, s in
                    if s == .thinking { withAnimation { proxy.scrollTo("bottom") } }
                }
                .onChange(of: store.partialTranscript) { _, _ in
                    proxy.scrollTo("bottom")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if let cid = store.currentConversationId {
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: { openWindow(id: "conversation-detail", value: cid) }) {
                        Label("Pop Out", systemImage: "rectangle.on.rectangle")
                    }
                    .help("Open this thread in its own window")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: { store.newConversation() }) {
                    Label("New Thread", systemImage: "plus.bubble")
                }
                .help("Start a fresh conversation")
            }
        }
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

// MARK: - Message rows

struct MessageRow: View {
    let message: ChatMessage
    private var isEve: Bool { message.role == .assistant }

    var body: some View {
        Group {
            if isEve { EveMessage(text: message.content) }
            else      { UserMessage(text: message.content) }
        }
    }
}

struct EveMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(C.eve)
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                Text("Eve")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(C.eve)
                Text(MentionRenderer.attributed(text))
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if MentionRenderer.handle(url: url) { return .handled }
                        return .systemAction
                    })
            }
            Spacer(minLength: 0)
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
}

struct UserMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 80)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(C.eve.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
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

// MARK: - Input bar

struct InputBar: View {
    @Binding var text: String
    @FocusState.Binding var inputFocused: Bool
    @Binding var showLauncher: Bool
    let usesLauncher: Bool
    @ObservedObject var store: LumenStore
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
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
                    .onSubmit(onSubmit)
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
                        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary), alignment: .trailing)

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
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(statusColor.opacity(0.3), lineWidth: 1))
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
        .background(isSelected ? Color.secondary.opacity(0.14) : (hovered ? Color.secondary.opacity(0.07) : Color.clear))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DetailMetric(title: "FINDINGS", value: "\(agent.totalFindings)", accent: .primary)
                DetailMetric(title: "STATUS", value: agent.status.uppercased(), accent: agent.status == "active" ? C.listen : C.eve)
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
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
    }

    private func submitChat() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSendingChat else { return }
        chatInput = ""
        onSendChat(text)
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
                        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary), alignment: .trailing)

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
        .background(isSelected ? Color.secondary.opacity(0.14) : (hovered ? Color.secondary.opacity(0.07) : Color.clear))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DetailMetric(title: "CODENAME", value: op.codename, accent: C.eve)
                DetailMetric(title: "PRIORITY", value: op.priority.uppercased(), accent: priorityColor)
                DetailMetric(title: "STATUS", value: op.status.uppercased(), accent: op.status == "active" ? C.listen : .primary)
                DetailMetric(title: "RECORDS", value: "\(records.count)", accent: C.think)
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
                            .foregroundColor(activeBriefKind == kind ? .white : .secondary.opacity(0.45))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(activeBriefKind == kind ? C.eve.opacity(0.15) : C.surfaceHi)
                            .overlay(Capsule().strokeBorder(activeBriefKind == kind ? C.eve.opacity(0.4) : C.hairline, lineWidth: 1))
                            .clipShape(Capsule())
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
                        .background(C.surfaceHi)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(C.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .background(C.listen.opacity(0.1))
                        .overlay(Capsule().strokeBorder(C.listen.opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if showAddForm {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Record title", text: $newTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(C.surfaceHi)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        TextEditor(text: $newContent)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 11))
                            .frame(minHeight: 60, maxHeight: 100)
                            .padding(6)
                            .background(C.surfaceHi)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                            .foregroundColor(C.eve)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(C.eve.opacity(0.1))
                            .overlay(Capsule().strokeBorder(C.eve.opacity(0.4), lineWidth: 1))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .disabled(newTitle.isEmpty)
                        }
                    }
                    .padding(10)
                    .background(C.surfaceHi)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(C.hairline, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .background(C.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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
        .background(C.surfaceHi)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .background(hovered && !disabled ? color.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(disabled ? C.hairline : color.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary), alignment: .trailing)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.type.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)
                    Text(item.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.92))
                    Text("Priority \(item.priority) · target: \(item.target)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
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

    var body: some View {
        GeometryReader { proxy in
            let splitLayout = proxy.size.width > 860

            VStack(spacing: 0) {
                SheetHeader(title: "CONVERSATIONS", subtitle: "\(store.conversations.count) THREADS", onDismiss: onDismiss)

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
                    .background(C.eve.opacity(0.07))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(C.eve.opacity(0.12)), alignment: .bottom)
                }
                .buttonStyle(.plain)

                if splitLayout {
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 1) {
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
                            .padding(.bottom, 20)
                        }
                        .frame(width: 360)
                        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary), alignment: .trailing)

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
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
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
                        .padding(.bottom, 20)
                    }
                }
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
            .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)

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
                .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary), alignment: .trailing)

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
        .background(isSelected ? Color.secondary.opacity(0.14) : (hovered ? Color.secondary.opacity(0.07) : Color.clear))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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
        .background(isSelected ? Color.secondary.opacity(0.14) : (hovered ? Color.secondary.opacity(0.07) : Color.clear))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(10)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .padding(10)
        .background(C.surfaceHi)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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
                .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)

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
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary), alignment: .bottom)
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
