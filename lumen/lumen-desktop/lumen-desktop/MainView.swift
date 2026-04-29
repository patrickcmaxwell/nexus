import SwiftUI
import Combine

// MARK: - Color palette

fileprivate enum C {
    static let eve    = Color(red: 0.545, green: 0.361, blue: 0.965) // violet — Eve's identity
    static let bg     = Color(red: 0.028, green: 0.028, blue: 0.056) // deep navy-black
    static let listen = Color(red: 0.22,  green: 0.98,  blue: 0.49)  // emerald green
    static let think  = Color(red: 1.0,   green: 0.75,  blue: 0.0)   // amber
    static let danger = Color(red: 1.0,   green: 0.25,  blue: 0.20)  // red
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

    enum PanelType: Equatable { case none, agents, operations, chats }

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
        ZStack(alignment: .bottom) {
            BackgroundLayer()

            VStack(spacing: 0) {
                TopHUD(store: store, auth: auth, lmStatus: lmStatus)
                ConversationThread(store: store)
            }

            // Input bar pinned to bottom
            InputBar(
                text: $inputText,
                inputFocused: $inputFocused,
                showLauncher: $showLauncher,
                store: store,
                onSubmit: submitInput
            )

            // Command launcher — flies up above input bar
            if showLauncher {
                CommandLauncher(isShowing: $showLauncher, activePanel: $activePanel, store: store)
                    .padding(.bottom, 80)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
            }

            // Floating panel sheet from bottom
            if activePanel != .none {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { activePanel = .none } }
                    .transition(.opacity)

                PanelSheet(type: activePanel, store: store) {
                    withAnimation(.spring(response: 0.3)) { activePanel = .none }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showLauncher)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activePanel)
        .task { await store.fetchDashboard(); await pingLMStudio() }
    }

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await store.send(text) }
    }

    private func pingLMStudio() async {
        guard let url = URL(string: "http://localhost:1234/v1/models") else { lmStatus = .offline; return }
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

// MARK: - Background

struct BackgroundLayer: View {
    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()

            // Dot matrix
            Canvas { ctx, size in
                let spacing: CGFloat = 48
                ctx.opacity = 0.07
                var x: CGFloat = 0
                while x <= size.width {
                    var y: CGFloat = 0
                    while y <= size.height {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                            with: .color(.white)
                        )
                        y += spacing
                    }
                    x += spacing
                }
            }
            .ignoresSafeArea()

            // Atmospheric Eve glow
            RadialGradient(
                colors: [C.eve.opacity(0.055), Color.clear],
                center: .center, startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Top HUD

struct TopHUD: View {
    @ObservedObject var store: LumenStore
    let auth: AuthManager
    let lmStatus: MainView.LMStatus

    private var statusColor: Color {
        switch store.eveStatus {
        case .idle:      return .white.opacity(0.2)
        case .listening: return C.listen
        case .thinking:  return C.think
        case .speaking:  return C.eve
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {

            // ── Eve status ring (left) ──────────────────────────────────────
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
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(4)
                    Text(store.eveStatus.label)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(statusColor)
                        .tracking(2)
                        .animation(.easeInOut, value: store.eveStatus)
                }
            }

            Spacer()

            // ── Center: waveform or title ───────────────────────────────────
            Group {
                if store.eveStatus == .listening || store.eveStatus == .speaking {
                    WaveformView(audioLevel: store.audioLevel, color: statusColor)
                        .frame(width: 72, height: 18)
                } else {
                    Text("NEXUS · LUMEN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.1))
                        .tracking(6)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.eveStatus)

            Spacer()

            // ── Right cluster ───────────────────────────────────────────────
            HStack(spacing: 14) {
                // LM Studio status pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(lmStatus.isOnline ? C.listen : .white.opacity(0.15))
                        .frame(width: 4, height: 4)
                        .shadow(color: lmStatus.isOnline ? C.listen : .clear, radius: 4)
                    Text(lmStatus.label)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .tracking(1)
                        .lineLimit(1)
                }

                TimeDisplay()

                Button { auth.signOut() } label: {
                    Text("LOCK")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.07), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.02))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.05)), alignment: .bottom)
    }
}

// MARK: - Conversation thread

struct ConversationThread: View {
    @ObservedObject var store: LumenStore

    private var isHistory: Bool { store.loadedHistoryTitle != nil }
    private var displayMessages: [ChatMessage] { isHistory ? store.loadedHistory : store.messages }

    var body: some View {
        VStack(spacing: 0) {
            // History banner
            if let title = store.loadedHistoryTitle {
                HistoryBanner(title: title) { store.clearHistory() }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if displayMessages.isEmpty && !isHistory {
                            EmptyState()
                                .padding(.top, 100)
                        }

                        ForEach(displayMessages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                                .padding(.horizontal, 44)
                                .padding(.vertical, 4)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Thinking dots
                        if store.eveStatus == .thinking && !isHistory {
                            ThinkingDots()
                                .padding(.horizontal, 44)
                                .padding(.vertical, 4)
                                .transition(.opacity)
                        }

                        // Partial transcript
                        if !store.partialTranscript.isEmpty && !isHistory {
                            PartialTranscript(text: store.partialTranscript)
                                .padding(.horizontal, 44)
                                .padding(.vertical, 4)
                        }

                        // Error
                        if let err = store.lastError {
                            ErrorRow(text: err)
                                .padding(.horizontal, 44)
                                .padding(.vertical, 4)
                        }

                        Color.clear.frame(height: 96).id("bottom")
                    }
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
                .foregroundColor(.white.opacity(0.15))

            Text(title)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
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
        .padding(.horizontal, 44)
        .padding(.vertical, 10)
        .background(C.eve.opacity(0.04))
        .overlay(Rectangle().frame(height: 1).foregroundColor(C.eve.opacity(0.1)), alignment: .bottom)
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(C.eve.opacity(0.07), lineWidth: 1).frame(width: 80, height: 80)
                Circle().stroke(C.eve.opacity(0.12), lineWidth: 1).frame(width: 56, height: 56)
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundColor(C.eve.opacity(0.3))
            }
            VStack(spacing: 5) {
                Text("EVE IS STANDING BY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .tracking(4)
                Text("speak or type a directive")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.1))
                    .tracking(2)
            }
        }
        .frame(maxWidth: .infinity)
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
        HStack(alignment: .top, spacing: 14) {
            // Violet accent stripe
            LinearGradient(colors: [C.eve, C.eve.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                .frame(width: 2)
                .cornerRadius(1)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                Text("EVE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(C.eve.opacity(0.5))
                    .tracking(4)
                Text(text)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.88))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 64)
        }
    }
}

struct UserMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 96)
            VStack(alignment: .trailing, spacing: 5) {
                Text("YOU")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                    .tracking(4)
                Text(text)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineSpacing(5)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(5)
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
    @ObservedObject var store: LumenStore
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Mic
            Button {
                if store.fluidListening || store.eveStatus == .listening {
                    store.stopListening()
                    store.voice.stopSpeaking()
                } else {
                    store.startListening()
                }
            } label: {
                let active = store.fluidListening || store.eveStatus == .listening
                ZStack {
                    Circle()
                        .fill(active ? C.listen.opacity(0.12) : Color.white.opacity(0.04))
                    Circle()
                        .stroke(active ? C.listen.opacity(0.4) : Color.white.opacity(0.09), lineWidth: 1)
                    Image(systemName: active ? "mic.fill" : "mic")
                        .font(.system(size: 13))
                        .foregroundColor(active ? C.listen : .white.opacity(0.35))
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)

            // Text field
            HStack(spacing: 8) {
                TextField("", text: $text,
                    prompt: Text("Send a directive...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                )
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(onSubmit)

                if !text.isEmpty {
                    Button(action: onSubmit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(C.bg)
                            .frame(width: 22, height: 22)
                            .background(C.eve)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(inputFocused ? C.eve.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .cornerRadius(8)

            // Launcher toggle
            Button { withAnimation { showLauncher.toggle() } } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showLauncher ? C.eve.opacity(0.15) : Color.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(showLauncher ? C.eve.opacity(0.4) : Color.white.opacity(0.09), lineWidth: 1)
                    Image(systemName: showLauncher ? "xmark" : "square.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundColor(showLauncher ? C.eve : .white.opacity(0.35))
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            C.bg.opacity(0.95)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.05)), alignment: .top)
        )
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
            Tile(icon: "person.badge.shield.checkmark.fill", label: "AGENTS",  sub: "\(store.agents.count) UNITS",     available: true)  { activePanel = .agents;     isShowing = false },
            Tile(icon: "bolt.fill",                           label: "OPS",     sub: "\(store.operations.count) ACTIVE", available: true)  { activePanel = .operations; isShowing = false },
            Tile(icon: "bubble.left.and.bubble.right.fill",   label: "CHATS",   sub: "HISTORY",                         available: true)  { activePanel = .chats;      isShowing = false; Task { await store.fetchConversations() } },
            Tile(icon: "books.vertical.fill",                 label: "VAULT",   sub: "SOON",                            available: false) {},
            Tile(icon: "cpu.fill",                            label: "SYSTEM",  sub: "SOON",                            available: false) {},
            Tile(icon: "map.fill",                            label: "MAP",     sub: "SOON",                            available: false) {},
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COMMAND HUB")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(4)
                Spacer()
                Button { withAnimation { isShowing = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
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
                .fill(Color(red: 0.055, green: 0.055, blue: 0.1).opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
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
                        .foregroundColor(hovered && tile.available ? .white : .white.opacity(tile.available ? 0.55 : 0.2))
                        .tracking(2)
                    Text(tile.sub)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
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
        guard tile.available else { return .white.opacity(0.15) }
        return hovered ? C.eve : .white.opacity(0.4)
    }
    private var bgColor: Color {
        guard tile.available && hovered else { return .white.opacity(0.03) }
        return C.eve.opacity(0.1)
    }
    private var borderColor: Color {
        guard tile.available else { return .white.opacity(0.05) }
        return hovered ? C.eve.opacity(0.35) : .white.opacity(0.07)
    }
}

// MARK: - Panel sheet (rises from bottom)

struct PanelSheet: View {
    let type: MainView.PanelType
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 32, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                switch type {
                case .agents:     AgentPanel(agents: store.agents, onDismiss: onDismiss)
                case .operations: OpsPanel2(operations: store.operations, onDismiss: onDismiss)
                case .chats:      ChatsPanel(store: store, onDismiss: onDismiss)
                case .none:       EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 500)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.055, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 50, y: -20)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Panel: Agents

struct AgentPanel: View {
    let agents: [AgentStatus]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "AGENT ROSTER", subtitle: "\(agents.count) UNITS", onDismiss: onDismiss)
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(agents) { AgentRow(agent: $0) }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentStatus
    @State private var hovered = false

    private var statusColor: Color {
        switch agent.status {
        case "active":    return C.listen
        case "deployed":  return C.eve
        default:          return .white.opacity(0.25)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(statusColor).frame(width: 6, height: 6).shadow(color: statusColor, radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(agent.status.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(statusColor.opacity(0.3), lineWidth: 1))
                }
                Text(agent.role)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                Text(agent.lastAction)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
        .background(hovered ? Color.white.opacity(0.03) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.05)), alignment: .bottom)
        .onHover { hovered = $0 }
    }
}

// MARK: - Panel: Operations

struct OpsPanel2: View {
    let operations: [OperationItem]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "OPERATIONS", subtitle: "\(operations.count) ACTIVE", onDismiss: onDismiss)
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(operations) { OpsRow2(op: $0) }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

private struct OpsRow2: View {
    let op: OperationItem
    @State private var hovered = false

    private var priorityColor: Color {
        switch op.priority {
        case "high":   return C.danger
        case "medium": return C.think
        default:       return .white.opacity(0.25)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 1).fill(priorityColor).frame(width: 2, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(op.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text(op.status.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(op.status == "active" ? C.listen : .white.opacity(0.3))
                }
                Text(op.priority.uppercased() + " PRIORITY")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(priorityColor.opacity(0.7))
                    .tracking(1)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(hovered ? Color.white.opacity(0.03) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.05)), alignment: .bottom)
        .onHover { hovered = $0 }
    }
}

// MARK: - Panel: Chats

struct ChatsPanel: View {
    @ObservedObject var store: LumenStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "CONVERSATIONS", subtitle: "\(store.conversations.count) THREADS", onDismiss: onDismiss)

            // New conversation
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

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.conversations) { conv in
                        ChatRow2(conv: conv)
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
        .task { await store.fetchConversations() }
    }
}

private struct ChatRow2: View {
    let conv: ConversationSummary
    @State private var hovered = false

    private var sourceColor: Color {
        conv.source == "lumen" ? C.eve : C.listen
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(sourceColor).frame(width: 5, height: 5).shadow(color: sourceColor, radius: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(conv.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)
                Text(conv.updatedAt.lumenRelative)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.15))
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(hovered ? Color.white.opacity(0.03) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.05)), alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Sheet header

struct SheetHeader: View {
    let title: String
    let subtitle: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .tracking(2)
                Text(subtitle)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(1)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)
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
                .foregroundColor(.white.opacity(0.3))
            Text(time, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.15))
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
