// ContentView.swift
// Nexus iOS — main voice interface

import SwiftUI
import PhotosUI
import UserNotifications

struct ContentView: View {
    @StateObject private var voice = EveVoiceManager()
    @State private var sessionId: String? = NexusAPIClient.shared.sessionId
    @State private var activeProfile: NexusAPIClient.ActiveProfile? = nil
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showCommandCenter = false
    @State private var showQuickCapture = false
    @State private var showGlobalSearch = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var tab: Tab = .voice
    @State private var composeText: String = ""
    /// True until the user passes the biometric gate on launch (only set
    /// when biometrics are enabled AND there's a cached session). When
    /// true, we hide the authenticated UI behind a Face ID prompt.
    @State private var biometricsLocked: Bool = EveBiometrics.shared.shouldUnlockOnLaunch
    @FocusState private var composeFocused: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case voice, dashboard, operations, agents, schedules, terminals, map, brain, connections, briefing, arena
        var id: String { rawValue }
        var label: String {
            switch self {
            case .voice:       return "EVE"
            case .dashboard:   return "DASH"
            case .operations:  return "OPS"
            case .agents:      return "AGENTS"
            case .schedules:   return "SCHED"
            case .terminals:   return "TERM"
            case .map:         return "MAP"
            case .brain:       return "BRAIN"
            case .connections: return "CONNECT"
            case .briefing:    return "BRIEF"
            case .arena:       return "ARENA"
            }
        }
        var icon: String {
            switch self {
            case .voice:       return "waveform"
            case .dashboard:   return "rectangle.grid.2x2.fill"
            case .operations:  return "square.stack.3d.up"
            case .agents:      return "person.2"
            case .schedules:   return "calendar"
            case .terminals:   return "terminal"
            case .map:         return "network"
            case .brain:       return "brain.head.profile"
            case .connections: return "link.circle"
            case .briefing:    return "newspaper"
            case .arena:       return "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if sessionId == nil {
                PinAuthView { sid in
                    sessionId = sid
                    biometricsLocked = false
                    Task { await refreshActiveProfile() }
                }
            } else if biometricsLocked {
                BiometricLockView(
                    onUnlock: {
                        biometricsLocked = false
                        Task { await refreshActiveProfile() }
                    },
                    onSkipToPIN: {
                        // User chose to sign out and re-PIN — common when
                        // biometrics fail repeatedly or the device owner
                        // changed.
                        NexusAPIClient.shared.logout()
                        sessionId = nil
                        biometricsLocked = false
                    }
                )
            } else {
                authenticatedView
            }
        }
        .animation(.easeInOut, value: sessionId)
        // On launch, validate the cached cookie against /api/auth/me. If
        // the server-side session has been invalidated (e.g. someone
        // switched users on Lumen or web), drop the local cache so the
        // user gets the fresh PIN screen instead of mysterious 401s.
        .task {
            if sessionId != nil { await refreshActiveProfile() }
            // Ambient sensors come up after auth — we never want to ask
            // for location on the PIN screen.
            EveAmbientContext.shared.start()
        }
        // Process the share-extension queue every time the app comes to
        // the foreground. Items captured while the main app was suspended
        // get folded into a fresh Eve message on return.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            consumeShareQueue()
            consumeNewConversationIntent()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onLogout: {
                NexusAPIClient.shared.logout()
                EveSpotlight.wipe()  // remove the previous user's titles from system search
                sessionId = nil
                activeProfile = nil
                showSettings = false
            })
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(onLoad: { id, history in
                voice.loadConversation(id: id, history: history)
                showHistory = false
            })
        }
        .fullScreenCover(isPresented: $showCommandCenter) {
            CommandCenterView(
                profile: activeProfile,
                voice: voice,
                onDismiss: { showCommandCenter = false },
                onOpenSettings: {
                    showCommandCenter = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showSettings = true
                    }
                },
                onOpenHistory: {
                    showCommandCenter = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showHistory = true
                    }
                },
                onSignOut: {
                    NexusAPIClient.shared.logout()
                    EveSpotlight.wipe()
                    sessionId = nil
                    activeProfile = nil
                    showCommandCenter = false
                }
            )
            .preferredColorScheme(.dark)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .preferredColorScheme(.dark)
    }

    /// Fetch the active human profile from /api/auth/me. Returns silently
    /// on success — the rendered top bar reads `activeProfile` directly.
    /// On 401 / nil response, drops the cached session so the PIN gate
    /// reappears instead of failing on every subsequent API call.
    private func refreshActiveProfile() async {
        let profile = await NexusAPIClient.shared.fetchActiveProfile()
        await MainActor.run {
            if let profile {
                self.activeProfile = profile
            } else {
                NexusAPIClient.shared.logout()
                self.activeProfile = nil
                self.sessionId = nil
            }
        }
    }

    /// Identity icon — single circular avatar pinned top-right. Tapping
    /// opens the full-screen Command Center, which mirrors Lumen's
    /// sidebar pattern (identity is also the control surface). Keeping
    /// the top nav strictly horizontal-scroll for tabs and reserving the
    /// avatar for a deep control surface gives both halves room.
    @ViewBuilder
    private func identityButton(_ profile: NexusAPIClient.ActiveProfile) -> some View {
        Button {
            Haptics.tap()
            showCommandCenter = true
        } label: {
            ZStack {
                Circle()
                    .fill(profile.isOwner ? Color.indigo.opacity(0.28) : Color.gray.opacity(0.18))
                Circle()
                    .stroke(profile.isOwner ? Color.indigo.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 1)
                Text(profile.avatarInitial)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(profile.isOwner ? .indigo : .white.opacity(0.85))
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open command center for \(profile.displayName)")
    }

    private var authenticatedView: some View {
        ZStack(alignment: .bottomTrailing) {
            authenticatedStack
            // Quick Capture FAB — overlay on every tab except Eve (where
            // typing directly into the composer is faster). Tap opens a
            // sheet that POSTs through askHomeBrain to the current Eve
            // conversation. Replies arrive in the Eve tab so the user can
            // stay focused on whatever surface they were inspecting.
            if tab != .voice {
                Button(action: { Haptics.tap(); showQuickCapture = true }) {
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.indigo, Color.indigo.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: Color.indigo.opacity(0.35), radius: 12, y: 4)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 24)
                .accessibilityLabel("Quick capture to Eve")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
        .sheet(isPresented: $showQuickCapture) {
            QuickCaptureSheet(onClose: { showQuickCapture = false }, voice: voice)
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchSheet(
                onClose: { showGlobalSearch = false },
                onJumpToTab: { newTab in
                    withAnimation(.easeInOut(duration: 0.18)) { tab = newTab }
                }
            )
        }
    }

    private var authenticatedStack: some View {
        VStack(spacing: 0) {
            // Top bar: scrollable tab strip + collapsed identity/control
            // menu pinned right. Combining the avatar + gear into one
            // Menu mirrors Lumen's sidebar pattern (identity is also the
            // control surface) and reclaims top-right real estate for the
            // wider tab strip.
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Tab.allCases) { t in tabButton(t) }
                    }
                    .padding(.vertical, 2)
                }
                Button(action: { Haptics.light(); showGlobalSearch = true }) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06))
                        Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Global search")
                if let profile = activeProfile {
                    identityButton(profile)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // Center the active tab's content and cap its width so iPad
            // doesn't stretch the layout edge-to-edge. iPhone hits the cap
            // on its own (max screen width is well under 720) so the
            // iPhone UX is unchanged.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    switch tab {
                    case .voice:       mainView
                    case .dashboard:   DashboardView(onJump: { newTab in
                                            withAnimation(.easeInOut(duration: 0.18)) { tab = newTab }
                                        })
                    case .operations:  OperationsListView()
                    case .agents:      AgentsListView()
                    case .schedules:   NavigationStack { SchedulesListView() }
                    case .terminals:   TerminalsListView()
                    case .map:         NavigationStack {
                                            NexusMapView(onJumpToTab: { newTab in
                                                withAnimation(.easeInOut(duration: 0.18)) { tab = newTab }
                                            })
                                        }
                    case .brain:       BrainView()
                    case .connections: ConnectionsListView()
                    case .briefing:    BriefingView()
                    case .arena:       ArenaLogView()
                    }
                }
                .frame(maxWidth: 720)
                Spacer(minLength: 0)
            }
        }
    }

    /// Drain the share extension's App Group queue. Each item becomes a
    /// fresh user-typed message into the active conversation.
    private func consumeShareQueue() {
        let appGroup = "group.io.talkcircles.nexus"
        let key = "share.queue"
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key)
        else { return }
        defaults.removeObject(forKey: key)

        struct Item: Decodable {
            enum Kind: String, Decodable { case text, url, image }
            let kind: Kind
            let value: String
            let imageData: Data?
        }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return }

        for item in items {
            switch item.kind {
            case .text, .url:
                voice.sendText(item.value)
            case .image:
                if let img = item.imageData { voice.attachImage(img) }
            }
        }
    }

    /// Honor a "new conversation" coming from the App Intent — we just
    /// tap the existing newConversation method when the flag is set.
    private func consumeNewConversationIntent() {
        guard UserDefaults.standard.bool(forKey: "nexus.intent.newConversation") else { return }
        UserDefaults.standard.removeObject(forKey: "nexus.intent.newConversation")
        voice.newConversation()
    }

    private func submitTypedMessage() {
        let text = composeText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Haptics.tap()
        composeText = ""
        composeFocused = false
        voice.sendText(text)
    }

    private func voiceOrSend() {
        if !voice.pendingImages.isEmpty {
            Haptics.tap()
            // Vision-only request: no transcribed text needed
            Task { await voice.askHomeBrain("") }
            return
        }
        // Entry to voice. If conversation mode is already on, this is a
        // no-op — the bottom row swaps to the Mute/End controls below.
        if voice.conversationMode { return }
        Haptics.heavy()
        voice.startConversation()
    }

    /// Top-strip tab pill. Selected gets a filled indigo background +
    /// white text; unselected stays text-only over the dark surface.
    /// SF Symbol icon sits inline at the left of the label so the strip
    /// reads at a glance without needing to know every short code (OPS,
    /// SCHED, TERM, etc).
    private func tabButton(_ value: Tab) -> some View {
        let selected = tab == value
        return Button {
            guard tab != value else { return }
            Haptics.light()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                tab = value
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: value.icon)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                Text(value.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
            }
            .foregroundColor(selected ? .white : Color.white.opacity(0.55))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(selected ? Color.indigo.opacity(0.9) : Color.white.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.indigo.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var mainView: some View {
        VStack(spacing: 30) {
            Spacer()

            // Eve identity
            VStack(spacing: 12) {
                Text("EVE")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.indigo)
                    .tracking(6)

                ZStack {
                    if voice.isListening {
                        Circle()
                            .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            .frame(width: 120, height: 120)
                            .scaleEffect(voice.isListening ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: voice.isListening)
                    }
                    Circle()
                        .fill(voice.isListening ? Color.indigo : Color.gray.opacity(0.2))
                        .frame(width: 88, height: 88)
                        .animation(.easeInOut(duration: 0.2), value: voice.isListening)
                }
            }

            // Live transcription (what user is saying)
            if !voice.transcribedText.isEmpty && voice.isListening {
                Text(voice.transcribedText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }

            // Conversation thread
            if !voice.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(voice.messages) { m in
                                IOSChatBubble(turn: m).id(m.id)
                            }
                            Color.clear.frame(height: 4).id("bottom")
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: voice.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // Status
            Text(voice.statusMessage)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            // Pending image strip
            if !voice.pendingImages.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.indigo)
                    Text("VISION · \(voice.pendingImages.count) image\(voice.pendingImages.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.indigo)
                    Spacer()
                    Button(action: { voice.clearPendingImages() }) {
                        Text("CLEAR")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.indigo.opacity(0.10))
                .overlay(Capsule().strokeBorder(Color.indigo.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
                .padding(.horizontal, 18)
                .transition(.opacity)
            }

            // Typed composer — type instead of speak when needed.
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $composeText,
                    prompt: Text("Type to Eve…").foregroundColor(.white.opacity(0.35))
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .tint(.indigo)
                    .focused($composeFocused)
                    .submitLabel(.send)
                    .onSubmit { submitTypedMessage() }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(composeFocused ? Color.indigo.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if !composeText.isEmpty {
                    Button(action: submitTypedMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.indigo)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .animation(.easeInOut(duration: 0.15), value: composeText.isEmpty)

            // Controls
            HStack(spacing: 8) {
                Button(action: { showHistory = true }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .frame(width: 50, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                }
                .help("Conversation history")

                Button(action: { voice.newConversation() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 50, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                }
                .help("New conversation")

                PhotosPicker(selection: $photoSelection, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: voice.pendingImages.isEmpty ? "photo" : "photo.fill")
                        .font(.system(size: 16))
                        .foregroundColor(voice.pendingImages.isEmpty ? .gray : .indigo)
                        .frame(width: 50, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke((voice.pendingImages.isEmpty ? Color.gray : Color.indigo).opacity(0.4), lineWidth: 1)
                        )
                }
                .onChange(of: photoSelection) { _, items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                voice.attachImage(data)
                            }
                        }
                        photoSelection = []
                    }
                }

                if voice.conversationMode {
                    // In conversation mode: Mute toggle (left) + End (right).
                    // Mic management is automatic — silence auto-submits,
                    // Eve's reply auto-resumes the mic. Mute is for "don't
                    // listen to me / the room right now"; End leaves
                    // conversation mode entirely.
                    Button(action: { Haptics.tap(); voice.toggleMute() }) {
                        HStack(spacing: 6) {
                            Image(systemName: voice.muted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(voice.muted ? "Unmute" : "Mute")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(voice.muted ? Color.gray.opacity(0.45) : Color.indigo.opacity(0.85))
                        )
                    }
                    Button(action: { Haptics.heavy(); voice.endConversation() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                            Text("End")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.red.opacity(0.75))
                        )
                    }
                } else {
                    Button(action: voiceOrSend) {
                        Text(voice.pendingImages.isEmpty ? "Talk to Eve" : "Ask Eve")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.indigo)
                            )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
            .animation(.easeInOut(duration: 0.2), value: voice.pendingImages.count)
            .animation(.easeInOut(duration: 0.18), value: voice.conversationMode)
        }
        .animation(.easeInOut, value: voice.isListening)
    }
}

// MARK: - Remote control panel

private struct ControlPanel: View {
    @State private var agents: [NexusAPIClient.AgentSummary] = []
    @State private var operations: [NexusAPIClient.OperationSummary] = []
    @State private var loading = true
    @State private var status = ""
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading {
                    Text("LOADING…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .tracking(2)
                        .padding(.top, 24)
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 20)
                }

                section(title: "AGENTS · \(agents.count)") {
                    ForEach(agents) { a in AgentRow(agent: a, onRun: { run(a) }, onToggle: { toggle(a) }) }
                }

                section(title: "OPERATIONS · \(operations.count)") {
                    ForEach(operations) { o in OperationRow(op: o, onCycle: { cycleOp(o) }) }
                }

                Button(action: { Task { await refresh() } }) {
                    Text("REFRESH")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.indigo)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.indigo.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .padding(.top, 12)
        }
        .task {
            await refresh()
            // Poll every 15s while this tab is visible.
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    if Task.isCancelled { break }
                    await refresh()
                }
            }
        }
        .onDisappear { refreshTask?.cancel() }
    }

    private func section<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 20)
            VStack(spacing: 6) { content() }
                .padding(.horizontal, 12)
        }
    }

    private func refresh() async {
        do {
            async let a = NexusAPIClient.shared.fetchAgents()
            async let o = NexusAPIClient.shared.fetchOperations()
            let (ag, op) = try await (a, o)
            await MainActor.run {
                self.agents = ag
                self.operations = op
                self.loading = false
            }
        } catch NexusAPIClient.APIError.unauthorized {
            await MainActor.run { self.status = "Session expired — re-auth" }
        } catch {
            await MainActor.run { self.status = "Refresh failed: \(error.localizedDescription)" }
        }
    }

    private func run(_ a: NexusAPIClient.AgentSummary) {
        Task {
            await MainActor.run { status = "Running \(a.name)…" }
            let ok = (try? await NexusAPIClient.shared.runAgent(id: a.id)) ?? false
            await MainActor.run { status = ok ? "✓ \(a.name) running" : "✗ Could not run \(a.name) (must be active)" }
            await refresh()
        }
    }

    private func toggle(_ a: NexusAPIClient.AgentSummary) {
        Task {
            let next = a.status == "active" ? "standby" : "active"
            await MainActor.run { status = "\(a.name) → \(next.uppercased())" }
            _ = try? await NexusAPIClient.shared.setAgentStatus(id: a.id, status: next)
            await refresh()
        }
    }

    private func cycleOp(_ o: NexusAPIClient.OperationSummary) {
        Task {
            let next: String
            switch o.status {
            case "planning": next = "active"
            case "active":   next = "paused"
            case "paused":   next = "active"
            case "complete": next = "planning"
            default:         next = "planning"
            }
            await MainActor.run { status = "\(o.name) → \(next.uppercased())" }
            _ = try? await NexusAPIClient.shared.setOperationStatus(id: o.id, status: next)
            await refresh()
        }
    }
}

private struct AgentRow: View {
    let agent: NexusAPIClient.AgentSummary
    let onRun: () -> Void
    let onToggle: () -> Void

    private var statusColor: Color {
        switch agent.status { case "active": return .green; case "standby": return .yellow; default: return .gray }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("\(agent.status.uppercased()) · \(agent.total_findings ?? 0) findings")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: agent.status == "active" ? "pause.fill" : "play.fill")
                    .foregroundColor(agent.status == "active" ? .yellow : .green)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
            Button(action: onRun) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.indigo)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct OperationRow: View {
    let op: NexusAPIClient.OperationSummary
    let onCycle: () -> Void

    private var statusColor: Color {
        switch op.status {
        case "active":   return .green
        case "planning": return .yellow
        case "paused":   return .orange
        case "complete": return .indigo
        case "aborted":  return .red
        default:         return .gray
        }
    }

    private var priorityColor: Color {
        switch op.priority {
        case "critical": return .red
        case "high":     return .orange
        case "medium":   return .indigo
        case "low":      return .gray
        default:         return .gray
        }
    }

    var body: some View {
        Button(action: onCycle) {
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(op.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(op.status.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(statusColor)
                        if let p = op.priority {
                            Text("·")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                            Text(p.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(priorityColor)
                        }
                    }
                }
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PIN auth gate

private struct PinAuthView: View {
    let onAuth: (String) -> Void

    @State private var email: String = UserDefaults.standard.string(forKey: "nexus.lastEmail") ?? ""
    @State private var digits: [String] = Array(repeating: "", count: 4)
    @State private var error: String = ""
    @State private var loading = false
    @State private var mode: Mode = .passcode
    @State private var showFaceSheet = false
    @FocusState private var emailFocused: Bool
    @FocusState private var focusedIndex: Int?

    enum Mode { case passcode, face }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("NEXUS")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.indigo)
                .tracking(8)

            // Mode toggle — mirrors Lumen Desktop's auth gate. PIN by
            // default; tap FACE to launch the camera-based flow.
            HStack(spacing: 0) {
                modeButton("PASSCODE", .passcode)
                modeButton("FACE", .face)
            }
            .frame(maxWidth: 240)
            .padding(3)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))

            // Email — identity hint that pins down which human's PIN we
            // verify against. Eliminates the multi-user PIN-collision bug
            // where two team members could share a 4-digit code.
            if mode == .passcode {
                TextField(
                    "",
                    text: $email,
                    prompt: Text("you@example.com").foregroundColor(.white.opacity(0.35))
                )
                    .textFieldStyle(.plain)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($emailFocused)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .tint(.indigo)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(emailFocused ? Color.indigo.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: email) { _, new in
                        email = new.lowercased().trimmingCharacters(in: .whitespaces)
                    }
                    .frame(maxWidth: 280)
                    .padding(.horizontal, 32)

                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        PinDigitField(
                            text: $digits[i],
                            focused: focusedIndex == i,
                            focus: $focusedIndex,
                            index: i,
                            onChange: { handleDigitChange(at: i) }
                        )
                    }
                }

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                }
                if loading {
                    Text("AUTHENTICATING…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .tracking(3)
                }
            } else {
                // FACE mode — big tap target launches the embedded face flow.
                Button {
                    showFaceSheet = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "faceid")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.indigo)
                        Text("SCAN FACE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(width: 240, height: 200)
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.indigo.opacity(0.4), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("Camera opens via the same web flow Lumen Desktop uses.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .sheet(isPresented: $showFaceSheet) {
            // Native AVFoundation capture → /api/security/face/match (server
            // runs face-api.js). This works in the simulator with camera
            // passthrough enabled (Simulator menu → Device → Connect
            // Hardware → Camera). The WebView path didn't because WKWebView
            // can't proxy getUserMedia to host hardware.
            NativeFaceCaptureSheet { sid in
                onAuth(sid)
            }
        }
        .onAppear {
            // Skip straight to PIN entry if we already have a cached email.
            if email.isEmpty { emailFocused = true }
            else { focusedIndex = 0 }
        }
    }

    private func modeButton(_ label: String, _ value: Mode) -> some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { mode = value } }) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(mode == value ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(mode == value ? Color.indigo.opacity(0.5) : Color.clear)
                )
        }
    }

    private func handleDigitChange(at i: Int) {
        var d = digits[i]
        if d.count > 1 { d = String(d.suffix(1)) }
        d = d.filter { $0.isNumber }
        digits[i] = d
        if !d.isEmpty && i < 3 { focusedIndex = i + 1 }
        if digits.allSatisfy({ !$0.isEmpty }) {
            Task { await submit() }
        }
    }

    private func submit() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else {
            await MainActor.run {
                self.error = "Email required"
                self.digits = Array(repeating: "", count: 4)
                self.emailFocused = true
            }
            return
        }
        loading = true
        defer { loading = false }
        let pin = digits.joined()
        do {
            let sid = try await NexusAPIClient.shared.authenticate(email: trimmedEmail, pin: pin)
            await MainActor.run { onAuth(sid) }
        } catch NexusAPIClient.APIError.unauthorized {
            await MainActor.run {
                self.error = "Wrong email or PIN"
                self.digits = Array(repeating: "", count: 4)
                self.focusedIndex = 0
            }
        } catch let NexusAPIClient.APIError.requestFailed(reason) {
            await MainActor.run {
                self.error = "Auth failed: \(reason)"
                self.digits = Array(repeating: "", count: 4)
                self.focusedIndex = 0
            }
        } catch {
            await MainActor.run {
                self.error = "Auth error: \(error.localizedDescription)"
                self.digits = Array(repeating: "", count: 4)
                self.focusedIndex = 0
            }
        }
    }
}

/// Three dots that bounce in sequence. Used inside an empty Eve bubble
/// while the streaming reply hasn't produced any text yet, so the user
/// sees "Eve heard me, working on it" instead of a silent empty box.
private struct ThinkingDots: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.indigo.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(scale(for: i))
                    .opacity(0.55 + 0.45 * scale(for: i))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func scale(for i: Int) -> Double {
        // Stagger each dot by ~0.2 phase units so they pulse in sequence.
        let local = (phase + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
        // Triangle wave 0→1→0 across one phase cycle
        return local < 0.5 ? 0.6 + local * 0.8 : 0.6 + (1 - local) * 0.8
    }
}

private struct IOSChatBubble: View {
    let turn: ChatTurn
    private var isEve: Bool { turn.role == .eve }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isEve {
                Text("EVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.indigo.opacity(0.7))
                    .tracking(2)
                    .frame(width: 28)
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Brain badge + ACTIONS pill — only on Eve replies that have metadata
                if isEve, (turn.brain != nil || !turn.toolCalls.isEmpty) {
                    HStack(spacing: 5) {
                        if let b = turn.brain {
                            Text(brainLabel(b))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(brainColor(b))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(brainColor(b).opacity(0.13))
                                .clipShape(Capsule())
                        }
                        if !turn.toolCalls.isEmpty {
                            Text("\(turn.toolCalls.count) ACTION\(turn.toolCalls.count == 1 ? "" : "S")")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.cyan.opacity(0.13))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Tool-call cards above prose so Eve's actions are visible
                if isEve, !turn.toolCalls.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(turn.toolCalls) { tc in
                            ToolCallCardiOS(summary: tc)
                        }
                    }
                }

                Group {
                    if isEve && turn.content.isEmpty {
                        // Pulsing dots while Eve is still streaming — gives
                        // the user a "she heard me, thinking" signal
                        // instead of an empty bubble that looks broken.
                        ThinkingDots()
                            .frame(height: 18)
                    } else {
                        Text(turn.content)
                            .font(.system(size: 13))
                            .foregroundColor(isEve ? .indigo.opacity(0.92) : .white.opacity(0.78))
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isEve ? Color.indigo.opacity(0.10) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isEve ? Color.indigo.opacity(0.25) : Color.white.opacity(0.10), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: isEve ? .leading : .trailing)
            }

            if !isEve {
                Text("YOU")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(2)
                    .frame(width: 28)
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 60)
            }
        }
    }

    private func brainLabel(_ b: String) -> String {
        switch b {
        case "grok":    return "GROK"
        case "local":   return "LOCAL"
        case "claude":  return "CLAUDE"
        case "vision":  return "VISION"
        case "offline": return "OFFLINE"
        default:        return b.uppercased()
        }
    }

    private func brainColor(_ b: String) -> Color {
        switch b {
        case "grok":    return .indigo
        case "local":   return .cyan
        case "claude":  return .orange
        case "vision":  return .cyan
        case "offline": return .gray
        default:        return .gray
        }
    }
}

/// iOS variant of the tool-call card — same data shape as Lumen + nexus-web.
private struct ToolCallCardiOS: View {
    let summary: ToolCallSummary

    private var accent: Color {
        if !summary.success { return .red }
        switch summary.name {
        case _ where summary.name.hasPrefix("arena_payment"): return .red
        case _ where summary.name.hasPrefix("arena_sync"):    return .indigo
        case _ where summary.name.hasPrefix("arena_task"):    return .cyan
        default:                                              return .indigo
        }
    }

    private var icon: String {
        if !summary.success { return "exclamationmark.triangle.fill" }
        switch summary.name {
        case "arena_task_create":  return "checkmark.seal.fill"
        case "arena_task_update":  return "pencil.circle.fill"
        case "arena_payment_route": return "dollarsign.circle.fill"
        case "arena_sync_push":    return "arrow.up.to.line.circle.fill"
        case "arena_recent":       return "list.bullet.rectangle.portrait.fill"
        default:                   return "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(summary.humanLabel.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(accent)
                    if !summary.success {
                        Text("FAILED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.red)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(summary.primary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                if !summary.detail.isEmpty {
                    Text(summary.detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(accent.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.32), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PinDigitField: View {
    @Binding var text: String
    let focused: Bool
    var focus: FocusState<Int?>.Binding
    let index: Int
    let onChange: () -> Void

    var body: some View {
        TextField("", text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 56, height: 64)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.indigo : Color.white.opacity(0.15), lineWidth: 1)
            )
            .focused(focus, equals: index)
            .onChange(of: text) { _, _ in onChange() }
    }
}

// MARK: - History (past conversations)

private struct HistoryView: View {
    let onLoad: (String, [NexusAPIClient.HistoryMessage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [NexusAPIClient.ConversationSummary] = []
    @State private var loading = true
    @State private var status: String = ""
    @State private var query: String = ""

    /// Filter conversations by title/source — title gets priority, source
    /// matches as a fallback so the user can find "all my Lumen sessions"
    /// or similar without needing a per-source filter UI.
    private var filtered: [NexusAPIClient.ConversationSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.lowercased().contains(q) || $0.source.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading conversations…")
                } else if conversations.isEmpty {
                    Text(status.isEmpty ? "No conversations yet." : status)
                        .foregroundColor(.secondary)
                        .padding()
                } else if filtered.isEmpty {
                    Text("No matches for \"\(query)\"")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(filtered) { c in
                        Button(action: { Task { await load(c) } }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.title.isEmpty ? "Untitled" : c.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(c.source.uppercased())
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.indigo)
                                    Text(formatDate(c.updated_at))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search conversations")
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        do {
            let list = try await NexusAPIClient.shared.fetchConversations()
            await MainActor.run {
                conversations = list
                loading = false
            }
            // Index every conversation into CoreSpotlight so iOS system
            // search hits Eve content. Cheap to call repeatedly — Spotlight
            // dedupes on uniqueIdentifier.
            EveSpotlight.reindex(list)
        } catch {
            await MainActor.run {
                loading = false
                status = "Could not load: \(error.localizedDescription)"
            }
        }
    }

    private func load(_ c: NexusAPIClient.ConversationSummary) async {
        do {
            let history = try await NexusAPIClient.shared.fetchHistory(conversationId: c.id)
            await MainActor.run {
                onLoad(c.id, history)
                dismiss()
            }
        } catch {
            await MainActor.run {
                status = "Could not load conversation: \(error.localizedDescription)"
            }
        }
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let s = -d.timeIntervalSinceNow
        if s < 60    { return "just now" }
        if s < 3600  { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        if s < 86400 * 7 { return "\(Int(s / 86400))d ago" }
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: d)
    }
}

// MARK: - Settings (base URL + logout)

private struct SettingsView: View {
    let onLogout: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL: String = UserDefaults.standard.string(forKey: "nexus.baseURL") ?? NexusAPIClient.publicBase
    @State private var localBrainURL: String = UserDefaults.standard.string(forKey: "nexus.localBrainURL") ?? ""
    @State private var localBrainModel: String = UserDefaults.standard.string(forKey: "nexus.localBrainModel") ?? "llama3.2:3b"
    @State private var voiceId: String = UserDefaults.standard.string(forKey: "nexus.voiceId") ?? "EXAVITQu4vr4xnSDxMaL"

    // Notification toggles — backed by UserDefaults so the future push
    // pipeline can read them server-side via device registration. Even
    // without server push wired up today, the toggles persist user intent.
    @AppStorage("nexus.notify.enabled")        private var notifyEnabled: Bool = false
    @AppStorage("nexus.notify.agentDone")      private var notifyAgentDone: Bool = true
    @AppStorage("nexus.notify.scheduleFired")  private var notifyScheduleFired: Bool = true
    @AppStorage("nexus.notify.researchDone")   private var notifyResearchDone: Bool = true
    @AppStorage("nexus.notify.opUpdated")      private var notifyOpUpdated: Bool = false

    // Refresh cadence shared with auto-refresh tasks (currently 30s in
    // AgentsListView / OperationsListView). Expose so the Director can
    // pick fresher data vs longer battery life.
    @AppStorage("nexus.cadence.list")          private var listCadenceSec: Int = 30

    @State private var notifPermStatus: String = "unknown"
    @State private var savedToast: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("NEXUS BASE URL") {
                    TextField("https://… or http://192.168.x.x:3000", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Text("Cloud: \(NexusAPIClient.publicBase)\nHome LAN: enter your Mac's IP + :3000")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("LOCAL BRAIN (DIRECT)") {
                    TextField("http://192.168.x.x:11434/v1/chat/completions", text: $localBrainURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Model name (e.g. llama3.2:3b)", text: $localBrainModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("When set and you say \"use local\", Eve hits your Mac's Ollama directly. Sub-second response on home wifi. Leave empty to always go through nexus-web.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("EVE VOICE (ELEVENLABS)") {
                    Picker("Voice", selection: $voiceId) {
                        Text("Bella · warm female").tag("EXAVITQu4vr4xnSDxMaL")
                        Text("Rachel · calm narrator").tag("21m00Tcm4TlvDq8ikWAM")
                        Text("Domi · confident").tag("AZnzlk1XvdvUeBnXmlld")
                        Text("Elli · young friendly").tag("MF3mGyEYCl7XYWbV9V6O")
                        Text("Antoni · smooth male").tag("ErXwobaYiN019PkySvjV")
                        Text("Adam · deep male").tag("pNInz6obpgDQGcFmaJgB")
                    }
                }
                Section {
                    Toggle("Enable notifications", isOn: $notifyEnabled)
                        .onChange(of: notifyEnabled) { _, newVal in
                            if newVal { requestNotificationPermission() }
                        }
                    if notifyEnabled {
                        Toggle("Agent finished a run", isOn: $notifyAgentDone)
                        Toggle("Schedule fired", isOn: $notifyScheduleFired)
                        Toggle("Research job complete", isOn: $notifyResearchDone)
                        Toggle("Operation status changed", isOn: $notifyOpUpdated)
                    }
                    Text(notifPermStatus.isEmpty ? "Permission state will appear here." : "iOS permission: \(notifPermStatus)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("NOTIFICATIONS")
                } footer: {
                    Text("Toggles persist your intent; server-side push delivery is wired up separately. The system permission prompt fires once when you enable.")
                }
                Section {
                    Picker("List refresh cadence", selection: $listCadenceSec) {
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("Manual only").tag(0)
                    }
                    Text("How often Operations / Agents lists auto-refresh. Manual = pull-to-refresh only (best battery).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("REFRESH CADENCE")
                }
                Section {
                    Button("Save") { save() }
                    if !savedToast.isEmpty {
                        Text(savedToast)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { onLogout() }
                }
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text("ABOUT")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { refreshPermissionStatus() }
        }
    }

    private func save() {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(trimmed, forKey: "nexus.baseURL")

        let lan = localBrainURL.trimmingCharacters(in: .whitespaces)
        if lan.isEmpty {
            UserDefaults.standard.removeObject(forKey: "nexus.localBrainURL")
        } else {
            UserDefaults.standard.set(lan, forKey: "nexus.localBrainURL")
        }

        let m = localBrainModel.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(m.isEmpty ? "llama3.2:3b" : m, forKey: "nexus.localBrainModel")
        UserDefaults.standard.set(voiceId, forKey: "nexus.voiceId")

        Haptics.success()
        savedToast = "Saved."
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedToast = "" }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted { notifyEnabled = false }
                refreshPermissionStatus()
            }
        }
    }

    private func refreshPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:        notifPermStatus = "Authorized"
                case .denied:            notifPermStatus = "Denied — fix in System Settings"
                case .notDetermined:     notifPermStatus = "Not asked yet"
                case .provisional:       notifPermStatus = "Provisional"
                case .ephemeral:         notifPermStatus = "Ephemeral"
                @unknown default:        notifPermStatus = "Unknown"
                }
            }
        }
    }
}

// MARK: - Briefing (what changed since last visit)

private struct BriefingView: View {
    @State private var briefing: NexusAPIClient.BriefingResponse?
    @State private var loading = true
    @State private var errorText: String = ""
    @ObservedObject private var ambient = EveAmbientContext.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !ambient.contextLine.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.indigo)
                        Text(ambient.contextLine)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 2)
                }
                if loading {
                    Text("LOADING BRIEFING…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray).tracking(2)
                        .padding(.top, 24)
                } else if let b = briefing {
                    headerStats(b.stats)
                    if !b.delta.newOperations.isEmpty {
                        section("NEW OPS") {
                            ForEach(b.delta.newOperations) { o in
                                operationRow(label: o.label, status: o.status, priority: o.priority)
                            }
                        }
                    }
                    if !b.delta.statusChangedOperations.isEmpty {
                        section("STATUS CHANGED") {
                            ForEach(b.delta.statusChangedOperations) { o in
                                operationRow(label: o.label, status: o.status, priority: o.priority)
                            }
                        }
                    }
                    if b.delta.findings.totalCount > 0 {
                        section("AGENT FINDINGS · \(b.delta.findings.totalCount)") {
                            ForEach(b.delta.findings.latest) { f in
                                findingRow(agent: f.agent, summary: f.summary ?? "")
                            }
                        }
                    }
                    if !b.delta.completedResearch.isEmpty {
                        section("COMPLETED RESEARCH") {
                            ForEach(b.delta.completedResearch) { r in
                                researchRow(label: r.operationLabel, summary: r.summary)
                            }
                        }
                    }
                    if b.delta.newOperations.isEmpty &&
                       b.delta.statusChangedOperations.isEmpty &&
                       b.delta.findings.totalCount == 0 &&
                       b.delta.completedResearch.isEmpty {
                        Text("Quiet on all fronts in the last 24 hours.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.top, 16)
                    }
                } else if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func headerStats(_ s: NexusAPIClient.BriefingStats) -> some View {
        HStack(spacing: 10) {
            statTile(title: "OPS",       value: s.activeOps)
            statTile(title: "AGENTS",    value: s.activeAgents)
            statTile(title: "DIRECTIVES", value: s.activeDirectives)
            statTile(title: "MEMORIES",  value: s.memories)
        }
    }

    @ViewBuilder
    private func statTile(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.indigo.opacity(0.8))
            content()
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func operationRow(label: String, status: String, priority: String?) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
            Spacer()
            Text(status.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(statusColor(status))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func findingRow(agent: String, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(agent)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5).foregroundColor(.indigo)
            Text(summary).font(.system(size: 12)).foregroundColor(.white.opacity(0.85)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func researchRow(label: String, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.isEmpty ? "—" : label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5).foregroundColor(.indigo)
            Text(summary).font(.system(size: 12)).foregroundColor(.white.opacity(0.85)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active":   return .green
        case "complete": return .blue
        case "paused":   return .yellow
        case "aborted":  return .red.opacity(0.8)
        default:         return .gray
        }
    }

    private func load() async {
        await MainActor.run { self.loading = true; self.errorText = "" }
        do {
            let b = try await NexusAPIClient.shared.fetchBriefing()
            await MainActor.run { self.briefing = b; self.loading = false }
        } catch {
            await MainActor.run {
                self.errorText = "Briefing unavailable: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }
}

// MARK: - Arena log (audit trail of Eve's tool calls)

private struct ArenaLogView: View {
    @State private var entries: [NexusAPIClient.ArenaEntry] = []
    @State private var loading = true
    @State private var errorText: String = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var search: String = ""

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, success, error
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private var filtered: [NexusAPIClient.ArenaEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { e in
            let statusOk: Bool
            switch statusFilter {
            case .all:     statusOk = true
            case .success: statusOk = e.status == "success" || e.status == nil  // null = legacy successes
            case .error:   statusOk = e.status == "error"
            }
            guard statusOk else { return false }
            if q.isEmpty { return true }
            return e.action.lowercased().contains(q)
                || (e.caller ?? "").lowercased().contains(q)
                || (e.error_msg ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    Text("ARENA · \(filtered.count)\(search.isEmpty && statusFilter == .all ? "" : " / \(entries.count)")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray).tracking(2)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    } else if filtered.isEmpty {
                        Text(emptyMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 24)
                            .padding(.horizontal, 20)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(filtered) { e in
                                ArenaEntryRow(entry: e)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search action / caller / error")
            .refreshable { await load() }
        }
        .task { await load() }
    }

    private var emptyMessage: String {
        if !errorText.isEmpty { return errorText }
        if !search.isEmpty || statusFilter != .all {
            return "No entries match this filter."
        }
        return "Eve hasn't fired any tools yet."
    }

    private func load() async {
        await MainActor.run { self.loading = true; self.errorText = "" }
        do {
            let r = try await NexusAPIClient.shared.fetchArenaLog(limit: 80)
            await MainActor.run { self.entries = r; self.loading = false }
        } catch {
            await MainActor.run {
                self.errorText = "Arena log unavailable: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }
}

private struct ArenaEntryRow: View {
    let entry: NexusAPIClient.ArenaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconForAction(entry.action))
                .font(.system(size: 13))
                .foregroundColor(success ? .green : .red.opacity(0.8))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.action)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    if let caller = entry.caller, !caller.isEmpty {
                        Text("· \(caller)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Text(relativeTime(entry.created_at))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                if let payload = entry.payload?.raw, !payload.isEmpty, payload != "{}" {
                    Text(payload)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
                if !success, let err = entry.error_msg, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var success: Bool {
        (entry.status ?? "ok").lowercased() != "error"
    }

    private func iconForAction(_ a: String) -> String {
        switch a {
        case let s where s.contains("task"):    return "checklist"
        case let s where s.contains("payment"): return "dollarsign.circle"
        case let s where s.contains("sync"):    return "arrow.triangle.2.circlepath"
        case let s where s.contains("recent"):  return "clock"
        default:                                return "bolt"
        }
    }

    private func relativeTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs/60)m" }
        if secs < 86_400 { return "\(secs/3600)h" }
        return "\(secs/86_400)d"
    }
}

// MARK: - Biometric lock screen

/// Tiny gate that runs the device's biometric prompt on first appearance
/// and falls back to a "Use PIN" button if the user cancels twice. Sits
/// between the PIN screen and the authenticated UI when a cached session
/// exists AND the user has biometric unlock enabled.
private struct BiometricLockView: View {
    let onUnlock: () -> Void
    let onSkipToPIN: () -> Void
    @State private var attempted = false
    @State private var error: String = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("NEXUS")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.indigo)
                .tracking(8)

            Image(systemName: EveBiometrics.shared.biometryName == "Touch ID" ? "touchid" : "faceid")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.indigo)

            Text(EveBiometrics.shared.biometryName.isEmpty
                 ? "Authenticating…"
                 : "Use \(EveBiometrics.shared.biometryName) to unlock")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button("Sign in with PIN instead") {
                onSkipToPIN()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !attempted else { return }
            attempted = true
            do {
                let ok = try await EveBiometrics.shared.authenticate(reason: "Unlock Nexus")
                if ok { onUnlock() }
                else { error = "Authentication canceled. Tap below to use PIN." }
            } catch {
                self.error = "Biometrics unavailable. Use PIN."
            }
        }
    }
}

// MARK: - Operations (list + detail)

private struct OperationsListView: View {
    @State private var operations: [NexusAPIClient.OperationSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var refreshTask: Task<Void, Never>?
    @State private var search: String = ""
    @State private var showCreate: Bool = false

    private var filtered: [NexusAPIClient.OperationSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return operations }
        return operations.filter { op in
            op.name.lowercased().contains(q)
                || (op.description ?? "").lowercased().contains(q)
                || op.status.lowercased().contains(q)
                || (op.priority ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.gray)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 20)
                    }
                    HStack {
                        Text("OPERATIONS · \(filtered.count)\(search.isEmpty ? "" : " / \(operations.count)")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Button(action: { Haptics.light(); showCreate = true }) {
                            Label("NEW", systemImage: "plus.circle.fill")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if filtered.isEmpty && !search.isEmpty && !loading {
                        Text("No operations match \"\(search)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    VStack(spacing: 6) {
                        ForEach(filtered) { op in
                            NavigationLink(value: op) { OperationListRow(op: op) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search operations")
            .refreshable { await refresh() }
            .navigationDestination(for: NexusAPIClient.OperationSummary.self) { op in
                OperationDetailView(operation: op)
            }
            .sheet(isPresented: $showCreate) {
                CreateOperationSheet { _ in
                    showCreate = false
                    Task { await refresh() }
                }
            }
        }
        .task {
            await refresh()
            refreshTask = Task {
                while !Task.isCancelled {
                    // User-configurable cadence (Settings → REFRESH CADENCE).
                    // 0 = manual-only, no auto-refresh loop.
                    let cadence = UserDefaults.standard.integer(forKey: "nexus.cadence.list")
                    let interval = cadence == 0 ? 30 : cadence
                    try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                    if Task.isCancelled { break }
                    if UserDefaults.standard.integer(forKey: "nexus.cadence.list") == 0 { continue }
                    await refresh()
                }
            }
        }
        .onDisappear { refreshTask?.cancel() }
    }

    private func refresh() async {
        do {
            let ops = try await NexusAPIClient.shared.fetchOperations()
            await MainActor.run {
                self.operations = ops
                self.loading = false
                self.error = nil
            }
        } catch NexusAPIClient.APIError.unauthorized {
            await MainActor.run { self.error = "Session expired" }
        } catch {
            await MainActor.run { self.error = "Refresh failed: \(error.localizedDescription)" }
        }
    }
}

private struct OperationListRow: View {
    let op: NexusAPIClient.OperationSummary

    private var statusColor: Color {
        switch op.status {
        case "active":   return .green
        case "planning": return .yellow
        case "paused":   return .orange
        case "complete": return .indigo
        case "aborted":  return .red
        default:         return .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(op.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(op.status.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(statusColor)
                    if let p = op.priority {
                        Text("·").font(.system(size: 9)).foregroundColor(.gray)
                        Text(p.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.6))
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

private struct OperationDetailView: View {
    let operation: NexusAPIClient.OperationSummary
    @State private var records: [NexusAPIClient.OperationRecord] = []
    @State private var briefs: [String: NexusAPIClient.OperationBrief] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var cycling = false
    @State private var showAddRecord = false
    @State private var showEdit = false
    @State private var showGenerateBrief = false
    @State private var statusOverride: String? = nil
    /// Record IDs with a research job kickoff in flight — disables the
    /// Research pill on that row until the request comes back.
    @State private var researching: Set<String> = []
    @State private var actionToast: String = ""
    /// Records view mode — flat list (default) or date-grouped timeline.
    /// Persists in UserDefaults so the Director's preference sticks
    /// across detail-screen visits.
    @AppStorage("nexus.opdetail.recordsMode") private var recordsMode: String = "list"

    private var currentStatus: String { statusOverride ?? operation.status }

    private let briefOrder = ["summary", "actions", "contradictions", "themes", "next-steps"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(operation.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        statusPill(currentStatus)
                        if let p = operation.priority { priorityPill(p) }
                    }
                    if let desc = operation.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)

                // Actions
                HStack(spacing: 8) {
                    Button(action: cycleStatus) {
                        Label(cycling ? "Updating…" : "Cycle status",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.indigo.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .disabled(cycling)

                    Button(action: { showAddRecord = true }) {
                        Label("Add record", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Menu {
                        Button {
                            showGenerateBrief = true
                        } label: {
                            Label("Generate brief…", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showEdit = true
                        } label: {
                            Label("Edit operation", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)

                if loading {
                    Text("LOADING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 16)
                }
                if !actionToast.isEmpty {
                    Text(actionToast)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.pink.opacity(0.85))
                        .padding(.horizontal, 16)
                }

                // Briefs
                if !briefs.isEmpty {
                    section("BRIEFS · \(briefs.count)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(briefOrder.filter { briefs[$0] != nil }, id: \.self) { kind in
                                if let b = briefs[kind] {
                                    briefCard(b)
                                }
                            }
                        }
                    }
                }

                // Records (with list/timeline toggle)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RECORDS · \(records.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Picker("Mode", selection: $recordsMode) {
                            Image(systemName: "list.bullet").tag("list")
                            Image(systemName: "clock.arrow.circlepath").tag("timeline")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                    }
                    .padding(.horizontal, 20)

                    if records.isEmpty {
                        Text("No records yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 16)
                    } else if recordsMode == "timeline" {
                        timelineView
                    } else {
                        VStack(spacing: 6) {
                            ForEach(records) { r in recordRow(r) }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 36)
            }
            .padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAddRecord) {
            AddRecordSheet(operationId: operation.id) { didAdd in
                showAddRecord = false
                if didAdd { Task { await load() } }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditOperationSheet(original: operation) { didSave in
                showEdit = false
                if didSave { Task { await load() } }
            }
        }
        .sheet(isPresented: $showGenerateBrief) {
            GenerateBriefSheet(operationId: operation.id) { didGenerate in
                showGenerateBrief = false
                if didGenerate { Task { await load() } }
            }
        }
    }

    /// Records grouped by day. Same row UI as the flat list, but each
    /// row sits under a sticky-style day header with a vertical timeline
    /// rail down the left margin. Reads better than the flat list when
    /// an operation has 20+ records across many days.
    @ViewBuilder
    private var timelineView: some View {
        let grouped = groupByDay(records)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(grouped, id: \.0) { day, rows in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.indigo.opacity(0.85)).frame(width: 7, height: 7)
                        Text(day.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.indigo.opacity(0.85))
                        Text("· \(rows.count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    // Vertical rail + indented rows
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1)
                            .padding(.leading, 19)
                        VStack(spacing: 6) {
                            ForEach(rows) { r in recordRow(r) }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                    }
                }
            }
        }
    }

    /// Group records by yyyy-MM-dd of created_at, sorted newest-first.
    /// Records with no parseable date land in an "UNDATED" bucket at end.
    private func groupByDay(_ rows: [NexusAPIClient.OperationRecord]) -> [(String, [NexusAPIClient.OperationRecord])] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let display = DateFormatter()
        display.dateStyle = .medium

        var buckets: [String: [NexusAPIClient.OperationRecord]] = [:]
        var order: [String] = []
        var bucketDate: [String: Date] = [:]

        for r in rows {
            let raw = r.created_at ?? ""
            let parsed = iso.date(from: raw) ?? isoBasic.date(from: raw)
            let label: String
            if let parsed {
                label = display.string(from: parsed)
                if bucketDate[label] == nil { bucketDate[label] = parsed }
            } else {
                label = "Undated"
            }
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(r)
        }

        // Sort buckets by date descending; "Undated" pinned at end.
        order.sort { a, b in
            if a == "Undated" { return false }
            if b == "Undated" { return true }
            return (bucketDate[a] ?? .distantPast) > (bucketDate[b] ?? .distantPast)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 20)
            content()
        }
    }

    private func briefCard(_ b: NexusAPIClient.OperationBrief) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(b.kind.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.indigo)
            Text(b.content)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private func recordRow(_ r: NexusAPIClient.OperationRecord) -> some View {
        let inFlight = researching.contains(r.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text((r.type ?? "note").uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
                if let p = r.priority {
                    Text("· \(p.uppercased())")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.gray)
                }
                Spacer()
                Button(action: { startResearch(r) }) {
                    HStack(spacing: 4) {
                        if inFlight {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(inFlight ? "QUEUEING" : "RESEARCH")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.pink.opacity(0.75))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            Text(r.title ?? "(untitled)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
            if let content = r.content, !content.isEmpty {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func startResearch(_ r: NexusAPIClient.OperationRecord) {
        Haptics.heavy()
        Task {
            await MainActor.run { researching.insert(r.id) }
            let ok = (try? await NexusAPIClient.shared.runRecordResearch(recordId: r.id)) ?? false
            await MainActor.run {
                researching.remove(r.id)
                actionToast = ok ? "Research queued" : "Research kickoff failed"
            }
            if ok {
                Haptics.success()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await load()
            } else {
                Haptics.error()
            }
            await MainActor.run { actionToast = "" }
        }
    }

    private func statusPill(_ status: String) -> some View {
        Text(status.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(statusColor(status))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(statusColor(status).opacity(0.12))
            .clipShape(Capsule())
    }

    private func priorityPill(_ priority: String) -> some View {
        Text(priority.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(.gray)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "active":   return .green
        case "planning": return .yellow
        case "paused":   return .orange
        case "complete": return .indigo
        case "aborted":  return .red
        default:         return .gray
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            async let r = NexusAPIClient.shared.fetchOperationRecords(operationId: operation.id)
            async let b = NexusAPIClient.shared.fetchOperationBriefs(operationId: operation.id)
            let (rec, br) = try await (r, b)
            await MainActor.run {
                self.records = rec
                self.briefs = br
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }

    private func cycleStatus() {
        Haptics.tap()
        Task {
            await MainActor.run { cycling = true }
            let next: String
            switch currentStatus {
            case "planning": next = "active"
            case "active":   next = "paused"
            case "paused":   next = "active"
            case "complete": next = "planning"
            default:         next = "planning"
            }
            await MainActor.run { statusOverride = next }
            let ok = (try? await NexusAPIClient.shared.setOperationStatus(id: operation.id, status: next)) ?? false
            await MainActor.run {
                cycling = false
                if !ok {
                    statusOverride = nil
                    error = "Status change failed."
                }
            }
        }
    }
}

// MARK: - Add Record sheet (operation detail → "+ Add record")

/// Quick "drop a note" entry sheet attached to an operation. Five fields:
/// title (required), content (long form), type, priority. POSTs through
/// NexusAPIClient.addOperationRecord. Designed for phone-thumb use — wide
/// text fields, big submit button, no nested navigation.
private struct AddRecordSheet: View {
    let operationId: String
    let onClose: (Bool) -> Void

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var type: String = "note"
    @State private var priority: String = "normal"
    @State private var submitting: Bool = false
    @State private var error: String = ""
    @FocusState private var titleFocused: Bool

    private let types = ["note", "intel", "finding", "data", "alert"]
    private let priorities = ["low", "normal", "high", "critical"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("TITLE")
                    TextField("e.g. Sheldon called back", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($titleFocused)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    fieldLabel("CONTENT")
                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 14))
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    fieldLabel("TYPE")
                    Picker("Type", selection: $type) {
                        ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    fieldLabel("PRIORITY")
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if submitting {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold))
                            }
                            Text(submitting ? "SAVING…" : "ADD RECORD")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(title.trimmingCharacters(in: .whitespaces).isEmpty || submitting
                                    ? Color.gray.opacity(0.3)
                                    : Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || submitting)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(false) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { titleFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundColor(.white.opacity(0.45))
    }

    private func submit() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""
        Task {
            do {
                let ok = try await NexusAPIClient.shared.addOperationRecord(
                    operationId: operationId,
                    title: t,
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    type: type,
                    priority: priority
                )
                await MainActor.run {
                    submitting = false
                    if ok {
                        Haptics.success()
                        onClose(true)
                    } else {
                        Haptics.error()
                        error = "Server refused the record."
                    }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Agents (list + detail)

private struct AgentsListView: View {
    @State private var agents: [NexusAPIClient.AgentSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var status: String = ""
    @State private var refreshTask: Task<Void, Never>?
    @State private var search: String = ""
    @State private var showCreate: Bool = false

    private var filtered: [NexusAPIClient.AgentSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return agents }
        return agents.filter { a in
            a.name.lowercased().contains(q)
                || (a.role ?? "").lowercased().contains(q)
                || a.status.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.gray)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    }
                    if !status.isEmpty {
                        Text(status)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 20)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 20)
                    }
                    HStack {
                        Text("AGENTS · \(filtered.count)\(search.isEmpty ? "" : " / \(agents.count)")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Button(action: { Haptics.light(); showCreate = true }) {
                            Label("NEW", systemImage: "plus.circle.fill")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if filtered.isEmpty && !search.isEmpty && !loading {
                        Text("No agents match \"\(search)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    VStack(spacing: 6) {
                        ForEach(filtered) { a in
                            NavigationLink(value: a) {
                                AgentListRow(agent: a,
                                             onRun: { run(a) },
                                             onToggle: { toggle(a) })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search agents")
            .refreshable { await refresh() }
            .navigationDestination(for: NexusAPIClient.AgentSummary.self) { a in
                AgentDetailView(agent: a)
            }
            .sheet(isPresented: $showCreate) {
                CreateAgentSheet { _ in
                    showCreate = false
                    Task { await refresh() }
                }
            }
        }
        .task {
            await refresh()
            refreshTask = Task {
                while !Task.isCancelled {
                    // User-configurable cadence (Settings → REFRESH CADENCE).
                    // 0 = manual-only, no auto-refresh loop.
                    let cadence = UserDefaults.standard.integer(forKey: "nexus.cadence.list")
                    let interval = cadence == 0 ? 30 : cadence
                    try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                    if Task.isCancelled { break }
                    if UserDefaults.standard.integer(forKey: "nexus.cadence.list") == 0 { continue }
                    await refresh()
                }
            }
        }
        .onDisappear { refreshTask?.cancel() }
    }

    private func refresh() async {
        do {
            let a = try await NexusAPIClient.shared.fetchAgents()
            await MainActor.run {
                self.agents = a
                self.loading = false
                self.error = nil
            }
        } catch NexusAPIClient.APIError.unauthorized {
            await MainActor.run { self.error = "Session expired" }
        } catch {
            await MainActor.run { self.error = "Refresh failed: \(error.localizedDescription)" }
        }
    }

    private func run(_ a: NexusAPIClient.AgentSummary) {
        Haptics.tap()
        Task {
            await MainActor.run { status = "Running \(a.name)…" }
            let ok = (try? await NexusAPIClient.shared.runAgent(id: a.id)) ?? false
            await MainActor.run {
                status = ok ? "✓ \(a.name) running" : "✗ Could not run \(a.name) (must be active)"
                if ok { Haptics.success() } else { Haptics.error() }
            }
            await refresh()
        }
    }

    private func toggle(_ a: NexusAPIClient.AgentSummary) {
        Haptics.light()
        Task {
            let next = a.status == "active" ? "standby" : "active"
            await MainActor.run { status = "\(a.name) → \(next.uppercased())" }
            _ = try? await NexusAPIClient.shared.setAgentStatus(id: a.id, status: next)
            await refresh()
        }
    }
}

private struct AgentListRow: View {
    let agent: NexusAPIClient.AgentSummary
    let onRun: () -> Void
    let onToggle: () -> Void

    private var statusColor: Color {
        switch agent.status { case "active": return .green; case "standby": return .yellow; default: return .gray }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("\(agent.status.uppercased()) · \(agent.total_findings ?? 0) findings")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: agent.status == "active" ? "pause.fill" : "play.fill")
                    .foregroundColor(agent.status == "active" ? .yellow : .green)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Button(action: onRun) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.indigo)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.6))
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

private struct AgentDetailView: View {
    let agent: NexusAPIClient.AgentSummary
    @State private var activity: [NexusAPIClient.AgentActivity] = []
    @State private var loading = true
    @State private var error: String?
    @State private var running = false
    @State private var togglingStatus = false
    @State private var showEdit = false
    /// Local override of the agent's status so the UI reflects an active/
    /// standby flip immediately without bouncing back to the parent list.
    @State private var statusOverride: String? = nil

    /// Active status driving the view — local override if set, else the
    /// parent-provided value. Refactored from raw `agent.status` so the
    /// toggle feels instant.
    private var currentStatus: String { statusOverride ?? agent.status }

    private var statusColor: Color {
        switch currentStatus { case "active": return .green; case "standby": return .yellow; default: return .gray }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        Text(currentStatus.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(statusColor.opacity(0.12))
                            .clipShape(Capsule())
                        if let r = agent.role {
                            Text(r.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(agent.total_findings ?? 0) findings")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Button(action: runNow) {
                        HStack(spacing: 8) {
                            if running {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "bolt.fill").font(.system(size: 13, weight: .bold))
                            }
                            Text(running ? "RUNNING…" : "RUN NOW")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: currentStatus == "active"
                                    ? [Color.indigo, Color.indigo.opacity(0.75)]
                                    : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(running || currentStatus != "active" || togglingStatus)

                    Button(action: toggleStatus) {
                        HStack(spacing: 6) {
                            if togglingStatus {
                                ProgressView().controlSize(.small).tint(.white.opacity(0.8))
                            } else {
                                Image(systemName: currentStatus == "active" ? "pause.fill" : "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(currentStatus == "active" ? "STANDBY" : "ACTIVATE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 14).padding(.vertical, 14)
                        .background(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(togglingStatus || running)
                }
                .padding(.horizontal, 16)

                if currentStatus != "active" {
                    Text("Activate the agent to run it.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 16)
                }

                if loading {
                    Text("LOADING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 16)
                }

                Text("ACTIVITY · \(activity.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if activity.isEmpty && !loading {
                    Text("No recent activity.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 6) {
                        ForEach(activity) { a in activityRow(a) }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showEdit = true }) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.indigo)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showEdit) {
            EditAgentSheet(original: agent) { didSave in
                showEdit = false
                if didSave { Task { await load() } }
            }
        }
    }

    private func activityRow(_ a: NexusAPIClient.AgentActivity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(a.action.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.indigo)
                Spacer()
                Text(a.created_at.prefix(19))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            }
            if let d = a.details?.raw, d != "{}", d != "null" {
                Text(d)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let a = try await NexusAPIClient.shared.fetchAgentActivity(agentId: agent.id)
            await MainActor.run {
                self.activity = a
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }

    private func runNow() {
        Haptics.heavy()
        Task {
            await MainActor.run { running = true }
            _ = try? await NexusAPIClient.shared.runAgent(id: agent.id)
            await MainActor.run { running = false }
            await load()
        }
    }

    private func toggleStatus() {
        Haptics.tap()
        let target = currentStatus == "active" ? "standby" : "active"
        Task {
            await MainActor.run {
                togglingStatus = true
                statusOverride = target
            }
            let ok = (try? await NexusAPIClient.shared.setAgentStatus(id: agent.id, status: target)) ?? false
            await MainActor.run {
                togglingStatus = false
                if !ok {
                    // Roll back optimistic flip on failure
                    statusOverride = nil
                    error = "Status change failed."
                }
            }
        }
    }
}

// MARK: - Schedules

private struct SchedulesListView: View {
    @State private var schedules: [NexusAPIClient.ScheduleSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search: String = ""
    /// IDs of schedules currently mid-action (toggle or run-now) so the
    /// UI can show a spinner and disable repeat taps.
    @State private var busy: Set<String> = []
    /// Optimistic enabled flags — flipped instantly on toggle so the UI
    /// feels responsive, then reconciled from the server response.
    @State private var enabledOverrides: [String: Bool] = [:]
    @State private var toast: String = ""
    @State private var showCreate: Bool = false

    private var filtered: [NexusAPIClient.ScheduleSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return schedules }
        return schedules.filter { s in
            s.name.lowercased().contains(q)
                || s.cron_expression.lowercased().contains(q)
                || s.target_type.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    Text("LOADING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.gray)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 20)
                }
                if !toast.isEmpty {
                    Text(toast)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.indigo.opacity(0.85))
                        .padding(.horizontal, 20)
                }
                HStack {
                    Text("SCHEDULES · \(filtered.count)\(search.isEmpty ? "" : " / \(schedules.count)")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Button(action: { Haptics.light(); showCreate = true }) {
                        Label("NEW", systemImage: "plus.circle.fill")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.indigo)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if schedules.isEmpty && !loading {
                    Text("No schedules yet. Tap + NEW to add one.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                } else if filtered.isEmpty && !search.isEmpty {
                    Text("No schedules match \"\(search)\"")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                VStack(spacing: 6) {
                    ForEach(filtered) { s in scheduleRow(s) }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search schedules")
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateScheduleSheet { _ in
                showCreate = false
                Task { await load() }
            }
        }
    }

    private func scheduleRow(_ s: NexusAPIClient.ScheduleSummary) -> some View {
        let isEnabled = enabledOverrides[s.id] ?? s.enabled
        let isBusy = busy.contains(s.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(s.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
                Text(s.target_type.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.gray)
            }
            HStack(spacing: 8) {
                Text(s.cron_expression)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.indigo.opacity(0.85))
                if let next = s.next_run_at {
                    Text("· next \(next.prefix(16))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            if let status = s.last_status {
                Text("last: \(status)\(s.last_error.map { " — \($0)" } ?? "")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(status == "success" ? .white.opacity(0.5) : .red.opacity(0.7))
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                // Enabled toggle — optimistic flip + server sync. Disabled
                // while in-flight so a double-tap can't desync state.
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newVal in Task { await setEnabled(id: s.id, to: newVal) } }
                ))
                .labelsHidden()
                .tint(.green)
                .disabled(isBusy)
                Text(isEnabled ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(isEnabled ? .green.opacity(0.85) : .gray)

                Spacer()

                Button(action: { Task { await fireNow(s) } }) {
                    HStack(spacing: 4) {
                        if isBusy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        }
                        Text("RUN NOW")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
            .padding(.top, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func setEnabled(id: String, to enabled: Bool) async {
        Haptics.tap()
        await MainActor.run {
            enabledOverrides[id] = enabled
            busy.insert(id)
        }
        do {
            let ok = try await NexusAPIClient.shared.setScheduleEnabled(id: id, enabled: enabled)
            if ok {
                await MainActor.run {
                    if let idx = schedules.firstIndex(where: { $0.id == id }) {
                        // ScheduleSummary is a let-struct; rebuild it with the
                        // new enabled flag so the next render picks it up.
                        let s = schedules[idx]
                        schedules[idx] = NexusAPIClient.ScheduleSummary(
                            id: s.id, name: s.name, description: s.description,
                            cron_expression: s.cron_expression, timezone: s.timezone,
                            target_type: s.target_type, target_id: s.target_id,
                            enabled: enabled, next_run_at: s.next_run_at,
                            last_run_at: s.last_run_at, last_status: s.last_status,
                            last_error: s.last_error
                        )
                    }
                    enabledOverrides.removeValue(forKey: id)
                    busy.remove(id)
                }
            } else {
                await rollback(id: id, message: "Toggle failed")
            }
        } catch {
            await rollback(id: id, message: "Toggle failed: \(error.localizedDescription)")
        }
    }

    private func fireNow(_ s: NexusAPIClient.ScheduleSummary) async {
        Haptics.heavy()
        await MainActor.run { busy.insert(s.id) }
        do {
            let ok = try await NexusAPIClient.shared.runScheduleNow(id: s.id)
            await MainActor.run {
                busy.remove(s.id)
                toast = ok ? "Fired: \(s.name)" : "Run failed: \(s.name)"
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { toast = "" }
            await load()
        } catch {
            await MainActor.run {
                busy.remove(s.id)
                toast = "Run failed: \(error.localizedDescription)"
            }
        }
    }

    private func rollback(id: String, message: String) async {
        await MainActor.run {
            enabledOverrides.removeValue(forKey: id)
            busy.remove(id)
            toast = message
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let s = try await NexusAPIClient.shared.fetchSchedules()
            await MainActor.run {
                self.schedules = s
                self.loading = false
                self.enabledOverrides.removeAll()
            }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }
}

// MARK: - Terminals (cross-device control of Lumen-spawned Claude Code sessions)

private struct TerminalsListView: View {
    @State private var sessions: [NexusAPIClient.TerminalSession] = []
    @State private var loading = true
    @State private var error: String?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.gray)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 20)
                    }

                    Text("TERMINALS · \(sessions.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if sessions.isEmpty && !loading {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No terminal sessions registered.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.45))
                            Text("Spawn a Claude Code session in Lumen on your Mac — it will appear here within a few seconds.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }

                    VStack(spacing: 6) {
                        ForEach(sessions) { s in
                            NavigationLink(value: s) { TerminalRow(session: s) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .refreshable { await refresh() }
            .navigationDestination(for: NexusAPIClient.TerminalSession.self) { s in
                TerminalDetailView(session: s)
            }
        }
        .task {
            await refresh()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if Task.isCancelled { break }
                    await refresh()
                }
            }
        }
        .onDisappear { refreshTask?.cancel() }
    }

    private func refresh() async {
        do {
            let s = try await NexusAPIClient.shared.fetchTerminalSessions()
            await MainActor.run {
                self.sessions = s
                self.loading = false
                self.error = nil
            }
        } catch NexusAPIClient.APIError.unauthorized {
            await MainActor.run { self.error = "Session expired" }
        } catch {
            await MainActor.run { self.error = "Refresh failed: \(error.localizedDescription)" }
        }
    }
}

private struct TerminalRow: View {
    let session: NexusAPIClient.TerminalSession

    private var statusColor: Color {
        switch session.status {
        case "running": return .green
        case "exited":  return .gray
        case "error":   return .red
        case "stale":   return .yellow
        default:        return .gray
        }
    }

    private var folderShort: String {
        // Display the last path component when the folder is long enough
        // that the full path would wrap awkwardly on a phone row.
        let parts = session.folder.split(separator: "/").map(String.init)
        return parts.last ?? session.folder
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? folderShort)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.status.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(statusColor)
                    if let mac = session.mac_label {
                        Text("· \(mac)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Text(session.folder)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.6))
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

private struct TerminalDetailView: View {
    let session: NexusAPIClient.TerminalSession
    @State private var live: NexusAPIClient.TerminalSession?
    @State private var commandText: String = ""
    @State private var sending = false
    @State private var sendStatus: String?
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    private var current: NexusAPIClient.TerminalSession { live ?? session }
    private var snapshot: String { current.last_snapshot ?? "" }
    private var running: Bool { current.status == "running" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip with folder + status
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title ?? current.folder)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    statusPill
                    if let mac = current.mac_label {
                        Text(mac)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    if let ts = current.last_snapshot_at {
                        Text("snap \(ts.prefix(19))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Text(current.folder)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)

            // Snapshot viewer — monospace; auto-scroll to bottom on update
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    Text(snapshot.isEmpty ? "(waiting for snapshot…)" : snapshot)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .id("term-bottom")
                }
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .onChange(of: snapshot) { _, _ in
                    withAnimation(.linear(duration: 0.15)) {
                        proxy.scrollTo("term-bottom", anchor: .bottom)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 14).padding(.top, 6)
            }
            if let sendStatus {
                Text(sendStatus)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.indigo)
                    .padding(.horizontal, 14).padding(.top, 6)
            }

            // Command composer
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $commandText,
                    prompt: Text(running ? "Send to PTY…" : "(session not running)")
                        .foregroundColor(.white.opacity(0.35))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(appendNewline: true) }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(inputFocused ? Color.indigo.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(!running)

                Button { send(appendNewline: true) } label: {
                    Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(running ? .indigo : .gray)
                }
                .disabled(!running || sending || commandText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Control keys row — Ctrl-C / Esc / Tab quick-sends for
            // terminal navigation. iOS keyboards don't have these.
            HStack(spacing: 8) {
                controlKey("⌃C")  { sendRaw("\u{03}") }       // SIGINT
                controlKey("ESC") { sendRaw("\u{1B}") }       // Escape
                controlKey("TAB") { sendRaw("\t") }
                controlKey("↑")   { sendRaw("\u{1B}[A") }     // arrow up
                controlKey("↓")   { sendRaw("\u{1B}[B") }     // arrow down
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if Task.isCancelled { break }
                    await load()
                }
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    private var statusPill: some View {
        Text(current.status.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(statusColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch current.status {
        case "running": return .green
        case "exited":  return .gray
        case "error":   return .red
        case "stale":   return .yellow
        default:        return .gray
        }
    }

    private func controlKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(!running || sending)
    }

    private func load() async {
        let fetched = try? await NexusAPIClient.shared.fetchTerminalSession(id: session.id)
        await MainActor.run {
            if let fetched { self.live = fetched }
        }
    }

    private func send(appendNewline: Bool) {
        let raw = commandText
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Haptics.tap()
        let payload = appendNewline ? raw + "\n" : raw
        commandText = ""
        sendRaw(payload)
    }

    private func sendRaw(_ payload: String) {
        Task {
            await MainActor.run { sending = true; sendStatus = "Sending…"; error = nil }
            do {
                let ok = try await NexusAPIClient.shared.submitTerminalCommand(
                    sessionId: session.id, command: payload
                )
                await MainActor.run {
                    sending = false
                    sendStatus = ok ? "Queued — Lumen will dispatch within ~5s" : "Submit failed"
                    if ok { Haptics.success() } else { Haptics.error() }
                }
            } catch {
                await MainActor.run {
                    sending = false
                    self.error = "Send failed: \(error.localizedDescription)"
                    self.sendStatus = nil
                    Haptics.error()
                }
            }
            // Fade the status message after a short window
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { if sendStatus?.hasPrefix("Queued") == true { sendStatus = nil } }
        }
    }
}

// MARK: - Command Center

/// Full-screen control panel reached by tapping the avatar in the top
/// nav. Inspired by Lumen's sidebar — identity at the top, then a stack
/// of grouped action rows. Animated entry/exit via fullScreenCover; rows
/// have a subtle stagger so the panel feels alive rather than static.
private struct CommandCenterView: View {
    let profile: NexusAPIClient.ActiveProfile?
    let voice: EveVoiceManager
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    let onSignOut: () -> Void

    @State private var appeared = false
    @State private var liveOps: Int? = nil
    @State private var liveAgents: Int? = nil
    @State private var liveTerminals: Int? = nil
    @State private var showTeam = false

    var body: some View {
        ZStack {
            // Background: deep tint + radial highlight at the avatar
            // origin so the entry feels rooted to where the tap happened.
            Color.black.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [Color.indigo.opacity(0.22), .clear]),
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.45), value: appeared)

            ScrollView {
                VStack(spacing: 22) {
                    header
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -12)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.04), value: appeared)

                    snapshotStrip
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.10), value: appeared)

                    conversationSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.16), value: appeared)

                    accountSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.22), value: appeared)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.light()
                withAnimation(.easeIn(duration: 0.18)) { appeared = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel("Close command center")
        }
        .onAppear {
            appeared = true
            Task { await loadSnapshot() }
        }
        .sheet(isPresented: $showTeam) {
            TeamListSheet(onClose: { showTeam = false })
        }
    }

    // MARK: Header (avatar + identity)

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: profile?.isOwner == true
                            ? [Color.indigo.opacity(0.55), Color.indigo.opacity(0.18)]
                            : [Color.gray.opacity(0.35), Color.gray.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                Text(profile?.avatarInitial ?? "?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 76, height: 76)
            .shadow(color: Color.indigo.opacity(0.4), radius: 18, x: 0, y: 6)

            Text(profile?.displayName ?? "—")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(profile?.email ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                if profile?.isOwner == true {
                    Text("OWNER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                } else if let role = profile?.role, !role.isEmpty {
                    Text(role.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.top, 28)
    }

    // MARK: System snapshot (live counts)

    private var snapshotStrip: some View {
        HStack(spacing: 10) {
            snapshotTile(label: "OPS",       value: liveOps,       icon: "square.stack.3d.up")
            snapshotTile(label: "AGENTS",    value: liveAgents,    icon: "person.2")
            snapshotTile(label: "TERMINALS", value: liveTerminals, icon: "terminal")
        }
    }

    private func snapshotTile(label: String, value: Int?, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.indigo)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: Section: conversation

    private var conversationSection: some View {
        section("CONVERSATION") {
            actionRow(icon: "plus.bubble", label: "New Conversation") {
                Haptics.tap()
                voice.newConversation()
                onDismiss()
            }
            actionRow(icon: "bubble.left.and.bubble.right", label: "Conversation History") {
                Haptics.light()
                onOpenHistory()
            }
            if voice.conversationMode {
                actionRow(icon: "mic.slash.fill",
                          label: voice.muted ? "Unmute Mic" : "Mute Mic",
                          accent: .indigo) {
                    Haptics.tap()
                    voice.toggleMute()
                }
                actionRow(icon: "xmark.circle.fill",
                          label: "End Conversation",
                          accent: .red) {
                    Haptics.heavy()
                    voice.endConversation()
                    onDismiss()
                }
            }
        }
    }

    // MARK: Section: account

    private var accountSection: some View {
        section("ACCOUNT") {
            actionRow(icon: "person.3.sequence.fill", label: "Team") {
                Haptics.light()
                showTeam = true
            }
            actionRow(icon: "gearshape", label: "Settings") {
                Haptics.light()
                onOpenSettings()
            }
            actionRow(icon: "arrow.right.square",
                      label: "Sign Out",
                      accent: .red) {
                Haptics.warning()
                onSignOut()
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.45))
                .padding(.leading, 4)
            VStack(spacing: 6) { content() }
        }
    }

    private func actionRow(icon: String,
                           label: String,
                           accent: Color = .white,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent == .white ? Color.white.opacity(0.06) : accent.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent == .white ? .white.opacity(0.85) : accent)
                }
                .frame(width: 30, height: 30)

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(accent == .red ? .red.opacity(0.95) : .white.opacity(0.9))

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Live snapshot

    /// Fire-and-forget fetches that populate the three snapshot tiles.
    /// Errors are silent — the tiles fall back to em-dashes if the call
    /// fails, since the Command Center should never block on the network.
    private func loadSnapshot() async {
        async let ops       = (try? await NexusAPIClient.shared.fetchOperations())?.count
        async let agents    = (try? await NexusAPIClient.shared.fetchAgents())?.count
        async let terminals = (try? await NexusAPIClient.shared.fetchTerminalSessions())?
            .filter { $0.status == "running" }.count
        let (o, a, t) = await (ops, agents, terminals)
        await MainActor.run {
            self.liveOps       = o
            self.liveAgents    = a
            self.liveTerminals = t
        }
    }
}

// MARK: - Connections (Arena providers — read-only visibility)

/// What providers (ClickUp / Notion / GitHub / Stripe / Slack) the user
/// has connected. Read-only: actual OAuth flows live on web — too much
/// browser-redirect ceremony to do nicely on phone. This view tells the
/// Director at a glance which integrations are wired and which are red.
private struct ConnectionsListView: View {
    @State private var connections: [NexusAPIClient.ArenaConnection] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    Text("LOADING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.gray)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 20)
                }
                Text("CONNECTIONS · \(connections.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if connections.isEmpty && !loading {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No connections wired yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Connect ClickUp, Notion, GitHub, Slack, or Stripe from the portal — they'll show up here once linked.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                VStack(spacing: 6) {
                    ForEach(connections) { c in connectionRow(c) }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func connectionRow(_ c: NexusAPIClient.ArenaConnection) -> some View {
        let statusColor: Color = {
            switch c.status {
            case "active":  return .green
            case "errored": return .red
            case "expired": return .orange
            default:        return .gray
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: providerIcon(c.provider))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.provider.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.9))
                    if let label = c.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(c.status.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(statusColor)
                }
            }
            if let last = c.last_used_at {
                Text("last used \(last.prefix(19))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            if let err = c.last_error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.75))
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider {
        case "clickup": return "checklist"
        case "notion":  return "doc.text.fill"
        case "github":  return "chevron.left.forwardslash.chevron.right"
        case "slack":   return "number"
        case "stripe":  return "creditcard.fill"
        default:        return "link.circle.fill"
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let c = try await NexusAPIClient.shared.fetchConnections()
            await MainActor.run {
                self.connections = c
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }
}

// MARK: - Nexus Map (phone-native rendering of the system graph)

/// The Nexus Map on web/Lumen is a force-directed graph of every entity
/// in the system. On a phone that visualization is unreadable, so iOS
/// renders the same data as a categorized browser: counts per node type
/// at the top, drill into a type for the full list, search across all
/// nodes. Same data contract (`/api/nexus-map`), different UX.
struct NexusMapView: View {
    /// Optional callback wired by ContentView so node detail can offer
    /// "Open in <tab>" jumps. nil = no jump capability (sheet still shows
    /// the node info, just without the jump button).
    var onJumpToTab: ((ContentView.Tab) -> Void)? = nil

    @State private var nodes: [NexusAPIClient.MapNode] = []
    @State private var edges: [NexusAPIClient.MapEdge] = []
    @State private var activeResearch: Int = 0
    @State private var loading = true
    @State private var error: String?
    @State private var search: String = ""
    @State private var selectedType: String? = nil
    @State private var inspectingNode: NexusAPIClient.MapNode? = nil
    /// Graph (luminous node/edge canvas, matching Lumen's 3D map) vs
    /// list (searchable per-row browser). Graph is the default —
    /// matches the desktop visual. Persists via UserDefaults.
    @AppStorage("nexus.map.mode") private var mapMode: String = "graph"

    /// Visible groups in the order we want them shown. Conversations are
    /// usually the highest-count noisy bucket so we put them last.
    private let typeOrder = ["operation", "agent", "record", "research", "topic", "directive", "human", "conversation"]

    private var filteredNodes: [NexusAPIClient.MapNode] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let inType: (NexusAPIClient.MapNode) -> Bool = { n in
            selectedType == nil || n.type == selectedType
        }
        if q.isEmpty {
            return nodes.filter(inType)
        }
        return nodes.filter { n in
            inType(n) && (
                n.title.lowercased().contains(q)
                    || n.subtitle.lowercased().contains(q)
                    || n.preview.lowercased().contains(q)
                    || n.tags.contains(where: { $0.lowercased().contains(q) })
            )
        }
    }

    private var counts: [(type: String, count: Int)] {
        let grouped = Dictionary(grouping: nodes, by: \.type)
        return typeOrder.compactMap { t in
            let c = grouped[t]?.count ?? 0
            return c > 0 ? (t, c) : nil
        }
    }

    var body: some View {
        Group {
            if mapMode == "graph" {
                graphMode
            } else {
                listMode
            }
        }
        .background(Color.black.ignoresSafeArea())
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $inspectingNode) { n in
            MapNodeDetailSheet(
                node: n,
                onClose: { inspectingNode = nil },
                onJumpToTab: onJumpToTab
            )
        }
    }

    /// Graph view — Canvas-rendered nodes + edges. Matches Lumen's 3D
    /// SceneKit map visually (just 2D) so the system feels coherent
    /// across surfaces. Type filter chips at top, graph in the middle,
    /// counts in the header. Tap a node to open the detail sheet.
    @ViewBuilder
    private var graphMode: some View {
        VStack(spacing: 0) {
            header

            if !counts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(label: "ALL", count: nodes.count, isActive: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(counts, id: \.type) { row in
                            chip(label: row.type.uppercased(), count: row.count, isActive: selectedType == row.type) {
                                selectedType = row.type == selectedType ? nil : row.type
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 6)
            }

            if loading {
                Spacer()
                Text("LOADING MAP…")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
            } else if filteredNodes.isEmpty {
                Spacer()
                Text(selectedType == nil ? "No nodes yet." : "No \(selectedType ?? "") nodes.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            } else {
                NexusMapGraph(
                    nodes: filteredNodes,
                    allNodes: nodes,
                    edges: edges,
                    highlightedType: selectedType,
                    onTapNode: { node in
                        Haptics.light()
                        inspectingNode = node
                    }
                )
            }
        }
    }

    /// List view — original phone-native browser. Useful when you want
    /// to scan/search rather than navigate visually.
    @ViewBuilder
    private var listMode: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.horizontal, 0)

                if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 20)
                }

                if !counts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(label: "ALL", count: nodes.count, isActive: selectedType == nil) {
                                selectedType = nil
                            }
                            ForEach(counts, id: \.type) { row in
                                chip(label: row.type.uppercased(), count: row.count, isActive: selectedType == row.type) {
                                    selectedType = row.type == selectedType ? nil : row.type
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if loading {
                    Text("LOADING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.gray)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity)
                } else if filteredNodes.isEmpty {
                    Text(search.isEmpty
                         ? "No \(selectedType ?? "nodes") yet."
                         : "No nodes match \"\(search)\".")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                } else {
                    Text("\(filteredNodes.count) shown")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 20)
                    VStack(spacing: 6) {
                        ForEach(filteredNodes.prefix(200)) { node in
                            nodeRow(node)
                        }
                        if filteredNodes.count > 200 {
                            Text("(\(filteredNodes.count - 200) more — refine search)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 36)
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the map")
    }

    /// Shared header — title, count, active-research line, plus the
    /// graph/list mode toggle pinned right.
    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXUS MAP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(.indigo.opacity(0.9))
                Text("\(nodes.count) nodes · \(edges.count) edges")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                if activeResearch > 0 {
                    Text("● \(activeResearch) research job\(activeResearch == 1 ? "" : "s") running")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green.opacity(0.85))
                }
            }
            Spacer()
            // Graph / list toggle — pinned in the header so the Director
            // can flip between visual and scan modes from any state.
            Picker("Mode", selection: $mapMode) {
                Image(systemName: "circle.grid.cross.fill").tag("graph")
                Image(systemName: "list.bullet").tag("list")
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func chip(label: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.light(); action() }) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? .black.opacity(0.6) : .white.opacity(0.5))
            }
            .foregroundColor(isActive ? .black : .white.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isActive ? Color.indigo.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func nodeRow(_ n: NexusAPIClient.MapNode) -> some View {
        Button(action: { Haptics.light(); inspectingNode = n }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: Self.iconFor(n.type))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Self.colorFor(n.type))
                        .frame(width: 18)
                    Text(n.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Text(n.type.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Self.colorFor(n.type).opacity(0.85))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                if !n.subtitle.isEmpty {
                    Text(n.subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                if !n.preview.isEmpty {
                    Text(n.preview)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    static func iconFor(_ type: String) -> String {
        switch type {
        case "conversation": return "bubble.left.and.bubble.right.fill"
        case "agent":        return "person.fill"
        case "operation":    return "square.stack.3d.up.fill"
        case "topic":        return "tag.fill"
        case "record":       return "doc.text.fill"
        case "research":     return "magnifyingglass"
        case "directive":    return "shield.lefthalf.filled"
        case "human":        return "person.crop.circle.fill"
        default:             return "circle.fill"
        }
    }

    static func colorFor(_ type: String) -> Color {
        switch type {
        case "conversation": return .blue
        case "agent":        return .green
        case "operation":    return .indigo
        case "topic":        return .orange
        case "record":       return .teal
        case "research":     return .pink
        case "directive":    return .yellow
        case "human":        return .purple
        default:             return .gray
        }
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let r = try await NexusAPIClient.shared.fetchNexusMap()
            await MainActor.run {
                self.nodes = r.nodes
                self.edges = r.edges ?? []
                self.activeResearch = r.activeResearch ?? 0
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Map unavailable: \(error.localizedDescription)"
                self.loading = false
            }
        }
    }
}

// MARK: - Create Operation sheet

private struct CreateOperationSheet: View {
    let onClose: (String?) -> Void   // returns new op id on success, nil on cancel

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var objectives: String = ""
    @State private var priority: String = "medium"
    @State private var status: String = "planning"
    @State private var submitting: Bool = false
    @State private var error: String = ""
    @FocusState private var nameFocused: Bool

    private let priorities = ["low", "medium", "high", "critical"]
    private let statuses = ["planning", "active", "paused", "complete", "aborted"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetField("NAME") {
                        TextField("e.g. Operation Sheldon", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .focused($nameFocused)
                    }
                    sheetField("DESCRIPTION") {
                        TextEditor(text: $description)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    sheetField("OBJECTIVES") {
                        TextEditor(text: $objectives)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    fieldLabel("PRIORITY")
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    fieldLabel("STATUS")
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton("CREATE OPERATION", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || submitting, busy: submitting, action: submit)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Operation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(nil) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { nameFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""
        Task {
            do {
                let newId = try await NexusAPIClient.shared.createOperation(
                    name: trimmed,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    objectives: objectives.trimmingCharacters(in: .whitespacesAndNewlines),
                    priority: priority,
                    status: status
                )
                await MainActor.run {
                    submitting = false
                    if newId != nil {
                        Haptics.success()
                        onClose(newId)
                    } else {
                        Haptics.error()
                        error = "Server didn't return an id."
                    }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Create failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Create Agent sheet

private struct CreateAgentSheet: View {
    let onClose: (String?) -> Void

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var personality: String = ""
    @State private var capabilitiesText: String = ""
    @State private var directives: String = ""
    @State private var status: String = "standby"
    @State private var submitting: Bool = false
    @State private var error: String = ""
    @FocusState private var nameFocused: Bool

    private let statuses = ["standby", "active", "offline"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetField("NAME") {
                        TextField("e.g. Researcher", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .focused($nameFocused)
                    }
                    sheetField("ROLE") {
                        TextField("e.g. Watch for product mentions", text: $role)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                    }
                    sheetField("PERSONALITY") {
                        TextEditor(text: $personality)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    sheetField("CAPABILITIES (comma-separated)") {
                        TextField("research, summarization", text: $capabilitiesText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                    }
                    sheetField("DIRECTIVES") {
                        TextEditor(text: $directives)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    fieldLabel("INITIAL STATUS")
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton(
                        "CREATE AGENT",
                        disabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                            || role.trimmingCharacters(in: .whitespaces).isEmpty
                            || submitting,
                        busy: submitting,
                        action: submit
                    )
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(nil) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { nameFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let r = role.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !r.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""

        let caps = capabilitiesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task {
            do {
                let newId = try await NexusAPIClient.shared.createAgent(
                    name: n,
                    role: r,
                    personality: personality.trimmingCharacters(in: .whitespacesAndNewlines),
                    capabilities: caps,
                    directives: directives.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: status
                )
                await MainActor.run {
                    submitting = false
                    if newId != nil {
                        Haptics.success()
                        onClose(newId)
                    } else {
                        Haptics.error()
                        error = "Server didn't return an id."
                    }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Create failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// Shared sheet primitives used by Create Operation / Agent / Record.
@ViewBuilder
private func sheetField<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        fieldLabel(label)
        content()
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private func fieldLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(2)
        .foregroundColor(.white.opacity(0.45))
}

private func submitButton(_ label: String, disabled: Bool, busy: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold))
            }
            Text(busy ? "SAVING…" : label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(disabled ? Color.gray.opacity(0.3) : Color.indigo)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
}

// MARK: - Dashboard (at-a-glance overview)

/// First-glance snapshot of the whole system: counts per surface, recent
/// arena activity, current focus. Pulls each surface's existing list endpoint
/// in parallel so the data is always live, not summarized server-side.
/// Lumen's dashboard is much richer; this is the phone equivalent —
/// landscape-readable at-a-glance state plus drill-in shortcuts.
private struct DashboardView: View {
    let onJump: (ContentView.Tab) -> Void

    @State private var opsCount = 0
    @State private var opsActive = 0
    @State private var agentsCount = 0
    @State private var agentsActive = 0
    @State private var schedulesCount = 0
    @State private var schedulesEnabled = 0
    @State private var terminalsCount = 0
    @State private var arenaRecent: [NexusAPIClient.ArenaEntry] = []
    @State private var activeResearch = 0
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    Text("LOADING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.gray)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 20)
                }

                // Active research banner — surfaces when the user has
                // research jobs in flight (kicked off via the Research
                // pill on operation records). Closes the feedback loop
                // so "is my research running?" is answerable from this
                // tab alone.
                if activeResearch > 0 {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.pink.opacity(0.18)).frame(width: 28, height: 28)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.pink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RESEARCH IN FLIGHT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.pink.opacity(0.9))
                            Text("\(activeResearch) job\(activeResearch == 1 ? "" : "s") running — findings will appear in their operations.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.pink.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.pink.opacity(0.35), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                }

                // 2-col tile grid for the counts
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile(title: "OPERATIONS", primary: "\(opsCount)", secondary: "\(opsActive) active", icon: "square.stack.3d.up.fill", color: .indigo, jumpTo: .operations)
                    tile(title: "AGENTS", primary: "\(agentsCount)", secondary: "\(agentsActive) active", icon: "person.2.fill", color: .green, jumpTo: .agents)
                    tile(title: "SCHEDULES", primary: "\(schedulesCount)", secondary: "\(schedulesEnabled) enabled", icon: "calendar", color: .blue, jumpTo: .schedules)
                    tile(title: "TERMINALS", primary: "\(terminalsCount)", secondary: "live PTYs", icon: "terminal.fill", color: .teal, jumpTo: .terminals)
                }
                .padding(.horizontal, 12)

                // Recent activity
                Text("RECENT ARENA · \(arenaRecent.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                if arenaRecent.isEmpty && !loading {
                    Text("Nothing fired yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 6) {
                        ForEach(arenaRecent.prefix(8)) { e in
                            recentRow(e)
                        }
                    }
                    .padding(.horizontal, 12)
                    Button(action: { Haptics.light(); onJump(.arena) }) {
                        Text("OPEN ARENA LOG →")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func tile(title: String, primary: String, secondary: String, icon: String, color: Color, jumpTo: ContentView.Tab) -> some View {
        Button(action: { Haptics.light(); onJump(jumpTo) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZStack {
                        Circle().fill(color.opacity(0.18)).frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(color)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                Text(primary)
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 4)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                Text(secondary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(color.opacity(0.85))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.025)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableTileStyle())
    }

    private func recentRow(_ e: NexusAPIClient.ArenaEntry) -> some View {
        let okColor: Color = e.status == "success" ? .green : (e.status == "error" ? .red : .gray)
        return HStack(spacing: 8) {
            Circle().fill(okColor).frame(width: 6, height: 6)
            Text(e.action.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Spacer()
            Text(e.created_at.prefix(16))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        async let ops       = (try? NexusAPIClient.shared.fetchOperations()) ?? []
        async let agents    = (try? NexusAPIClient.shared.fetchAgents()) ?? []
        async let schedules = (try? NexusAPIClient.shared.fetchSchedules()) ?? []
        async let terms     = (try? NexusAPIClient.shared.fetchTerminalSessions()) ?? []
        async let arena     = (try? NexusAPIClient.shared.fetchArenaLog(limit: 10)) ?? []
        // Nexus map provides the activeResearch heartbeat — same call the
        // Map tab uses. Heavier than the per-surface fetches but already
        // hot in cache from the Map tab if the user just visited it.
        async let map       = (try? NexusAPIClient.shared.fetchNexusMap())

        let (o, a, s, t, ar, m) = await (ops, agents, schedules, terms, arena, map)
        await MainActor.run {
            opsCount = o.count
            opsActive = o.filter { $0.status == "active" }.count
            agentsCount = a.count
            agentsActive = a.filter { $0.status == "active" }.count
            schedulesCount = s.count
            schedulesEnabled = s.filter { $0.enabled }.count
            terminalsCount = t.filter { $0.status == "running" || $0.status == "stale" }.count
            arenaRecent = ar
            activeResearch = m?.activeResearch ?? 0
            loading = false
        }
    }
}

// MARK: - Create Schedule sheet

/// Schedule creation on phone: preset-driven so the Director doesn't have
/// to remember cron syntax. Five presets cover the common cases; a "Custom"
/// option exposes the raw cron field for power users. Target picker depends
/// on type — eve_chat / agent_run / operation_brief require a target_id, and
/// we render a picker populated from the cached list view rather than
/// re-fetching here.
private struct CreateScheduleSheet: View {
    let onClose: (String?) -> Void

    @State private var name: String = ""
    @State private var preset: CronPreset = .dailyMorning
    @State private var customCron: String = "0 9 * * *"
    @State private var targetType: String = "operation_brief"
    @State private var targetId: String = ""
    @State private var payloadText: String = ""        // for operation_brief: kind name
    @State private var submitting: Bool = false
    @State private var error: String = ""
    @FocusState private var nameFocused: Bool

    // Caches loaded once on appear so the target picker has options.
    @State private var ops: [NexusAPIClient.OperationSummary] = []
    @State private var agents: [NexusAPIClient.AgentSummary] = []

    enum CronPreset: String, CaseIterable, Identifiable {
        case dailyMorning, dailyEvening, hourly, weekdays5pm, mondays9am, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dailyMorning: return "Daily 9am"
            case .dailyEvening: return "Daily 6pm"
            case .hourly:       return "Every hour"
            case .weekdays5pm:  return "Weekdays 5pm"
            case .mondays9am:   return "Mondays 9am"
            case .custom:       return "Custom…"
            }
        }
        var cron: String {
            switch self {
            case .dailyMorning: return "0 9 * * *"
            case .dailyEvening: return "0 18 * * *"
            case .hourly:       return "0 * * * *"
            case .weekdays5pm:  return "0 17 * * 1-5"
            case .mondays9am:   return "0 9 * * 1"
            case .custom:       return ""
            }
        }
    }

    private let targetTypes = ["operation_brief", "agent_run", "eve_chat", "arena_action"]

    private var effectiveCron: String {
        preset == .custom ? customCron.trimmingCharacters(in: .whitespaces) : preset.cron
    }

    private var requiresTargetId: Bool { targetType != "arena_action" }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !effectiveCron.isEmpty
            && (!requiresTargetId || !targetId.isEmpty)
            && !submitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetField("NAME") {
                        TextField("e.g. Morning Sheldon check-in", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .focused($nameFocused)
                    }

                    fieldLabel("WHEN")
                    Picker("When", selection: $preset) {
                        ForEach(CronPreset.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if preset == .custom {
                        sheetField("CRON EXPRESSION") {
                            TextField("min hour dom month dow", text: $customCron)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    } else {
                        Text(preset.cron)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.indigo.opacity(0.75))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    fieldLabel("TARGET")
                    Picker("Target type", selection: $targetType) {
                        ForEach(targetTypes, id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if targetType == "operation_brief" {
                        targetIdPicker(label: "OPERATION", options: ops.map { ($0.id, $0.name) })
                        sheetField("BRIEF KIND") {
                            TextField("summary, actions, next-steps", text: $payloadText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    } else if targetType == "agent_run" {
                        targetIdPicker(label: "AGENT", options: agents.map { ($0.id, $0.name) })
                    } else if targetType == "eve_chat" {
                        sheetField("CONVERSATION ID") {
                            TextField("eve_conversations.id", text: $targetId)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        Text("Tip: pick a conversation in the Eve tab and copy its id from history.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    } else {
                        Text("arena_action target — payload-driven, configure in portal.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton("CREATE SCHEDULE", disabled: !canSubmit, busy: submitting, action: submit)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(nil) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear {
                nameFocused = true
                Task { await loadTargets() }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func targetIdPicker(label: String, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            if options.isEmpty {
                Text("None loaded — type the id manually.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                TextField("\(label) id", text: $targetId)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Picker(label, selection: $targetId) {
                    Text("Select…").tag("")
                    ForEach(options, id: \.0) { id, name in
                        Text(name).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func loadTargets() async {
        async let o = (try? NexusAPIClient.shared.fetchOperations()) ?? []
        async let a = (try? NexusAPIClient.shared.fetchAgents()) ?? []
        let (loadedOps, loadedAgents) = await (o, a)
        await MainActor.run {
            self.ops = loadedOps
            self.agents = loadedAgents
        }
    }

    private func submit() {
        guard canSubmit else { return }
        Haptics.tap()
        submitting = true
        error = ""

        // Translate the iOS form into the server's payload shape.
        // operation_brief expects { kind: "summary"|... }; eve_chat takes
        // free-form message (we don't surface a payload field for it yet);
        // agent_run takes no payload.
        var payload: [String: Any] = [:]
        if targetType == "operation_brief" {
            let kind = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kind.isEmpty { payload["kind"] = kind } else { payload["kind"] = "summary" }
        }

        Task {
            do {
                let newId = try await NexusAPIClient.shared.createSchedule(
                    name: name.trimmingCharacters(in: .whitespaces),
                    cronExpression: effectiveCron,
                    targetType: targetType,
                    targetId: requiresTargetId ? targetId : nil,
                    timezone: TimeZone.current.identifier,
                    payload: payload,
                    enabled: true,
                    description: nil
                )
                await MainActor.run {
                    submitting = false
                    if newId != nil {
                        Haptics.success()
                        onClose(newId)
                    } else {
                        Haptics.error()
                        error = "Server didn't return an id."
                    }
                }
            } catch let NexusAPIClient.APIError.requestFailed(msg) {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    error = msg
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Create failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Quick Capture sheet (global FAB)

/// Drop-a-thought sheet reachable from any tab via the floating "+" FAB.
/// Same destination as the Eve tab composer — POSTs through askHomeBrain
/// — but opens as a sheet so the Director doesn't lose tab context.
/// Best used for "log this before I forget" moments while browsing Ops,
/// Agents, etc.
private struct QuickCaptureSheet: View {
    let onClose: () -> Void
    @ObservedObject var voice: EveVoiceManager

    @State private var text: String = ""
    @State private var submitting: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Eve will see this in the current conversation.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 4)

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .focused($fieldFocused)
                    .frame(minHeight: 160)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.indigo.opacity(fieldFocused ? 0.5 : 0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                submitButton(
                    "SEND TO EVE",
                    disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting,
                    busy: submitting,
                    action: send
                )

                Spacer()
            }
            .padding(16)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { fieldFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        // sendText is fire-and-forget — it spawns the Task internally and
        // appends to voice.messages. We dismiss immediately so the user
        // sees a clean "sent" feel; the reply lands in the Eve tab.
        voice.sendText(trimmed)
        Haptics.success()
        onClose()
    }
}

// MARK: - Map node detail sheet

/// Tap-to-inspect on Nexus Map nodes. Shows full title / subtitle / preview
/// / tags / timestamps. For node types that have a dedicated tab on iOS
/// (operations, agents), offers a one-tap pivot via a "filter by type"
/// nudge that closes the sheet and bounces the user to the right tab.
/// We don't navigate across tabs to a specific entity yet — that needs
/// cross-tab state plumbing.
private struct MapNodeDetailSheet: View {
    let node: NexusAPIClient.MapNode
    let onClose: () -> Void
    let onJumpToTab: ((ContentView.Tab) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: NexusMapView.iconFor(node.type))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(NexusMapView.colorFor(node.type))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                            Text(node.type.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(NexusMapView.colorFor(node.type).opacity(0.85))
                        }
                        Spacer()
                    }

                    if !node.subtitle.isEmpty {
                        Text(node.subtitle)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    if !node.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(node.tags, id: \.self) { tag in
                                Text(tag.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.2)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if !node.preview.isEmpty {
                        Text(node.preview)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(spacing: 16) {
                        timestamp("CREATED", node.createdAt)
                        timestamp("UPDATED", node.updatedAt)
                        if node.messageCount > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MSGS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.5)
                                    .foregroundColor(.white.opacity(0.4))
                                Text("\(node.messageCount)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }

                    if let pivotTab = pivotTab {
                        Button(action: { onJumpToTab?(pivotTab); onClose() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("OPEN IN \(pivotTab.label)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1.5)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    Spacer()
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pivotTab: ContentView.Tab? {
        switch node.type {
        case "operation":    return .operations
        case "agent":        return .agents
        case "conversation": return .voice
        default:             return nil
        }
    }

    private func timestamp(_ label: String, _ iso: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            Text(iso.prefix(16))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

/// Lightweight flow layout for tag chips — wraps to a new row when the
/// horizontal axis runs out. SwiftUI doesn't ship a flow layout primitive
/// pre-iOS 16, but iOS 16+ has the `Layout` protocol which gives us this.
private struct FlowLayout: Layout {
    let spacing: CGFloat
    init(spacing: CGFloat = 6) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth - spacing)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Edit Operation sheet

/// Reuses the Create sheet's shape but pre-populates fields from the
/// existing operation and posts via PATCH instead of POST. iOS gets full
/// CRU parity with Lumen — delete still goes through the portal because
/// destructive ops deserve more confirmation surface than a phone modal.
private struct EditOperationSheet: View {
    let original: NexusAPIClient.OperationSummary
    let onClose: (Bool) -> Void   // true = saved, false = cancelled

    @State private var name: String
    @State private var description: String
    @State private var objectives: String
    @State private var priority: String
    @State private var status: String
    @State private var submitting: Bool = false
    @State private var error: String = ""

    private let priorities = ["low", "medium", "high", "critical"]
    private let statuses = ["planning", "active", "paused", "complete", "aborted"]

    init(original: NexusAPIClient.OperationSummary, onClose: @escaping (Bool) -> Void) {
        self.original = original
        self.onClose = onClose
        _name = State(initialValue: original.name)
        _description = State(initialValue: original.description ?? "")
        _objectives = State(initialValue: "")  // not on summary; user re-enters or leaves blank
        _priority = State(initialValue: original.priority ?? "medium")
        _status = State(initialValue: original.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetField("NAME") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                    }
                    sheetField("DESCRIPTION") {
                        TextEditor(text: $description)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    sheetField("OBJECTIVES") {
                        TextEditor(text: $objectives)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    Text("Objectives weren't in the summary fetch; leave blank to keep the existing value.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))

                    fieldLabel("PRIORITY")
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    fieldLabel("STATUS")
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton(
                        "SAVE CHANGES",
                        disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || submitting,
                        busy: submitting,
                        action: submit
                    )
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit Operation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(false) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""
        let obj = objectives.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let ok = try await NexusAPIClient.shared.updateOperation(
                    id: original.id,
                    name: trimmed,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    objectives: obj.isEmpty ? nil : obj,
                    priority: priority,
                    status: status
                )
                await MainActor.run {
                    submitting = false
                    if ok {
                        Haptics.success()
                        onClose(true)
                    } else {
                        Haptics.error()
                        error = "Update failed."
                    }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Edit Agent sheet

private struct EditAgentSheet: View {
    let original: NexusAPIClient.AgentSummary
    let onClose: (Bool) -> Void

    @State private var name: String
    @State private var role: String
    @State private var personality: String
    @State private var capabilitiesText: String
    @State private var directives: String
    @State private var status: String
    @State private var submitting: Bool = false
    @State private var error: String = ""

    private let statuses = ["standby", "active", "offline"]

    init(original: NexusAPIClient.AgentSummary, onClose: @escaping (Bool) -> Void) {
        self.original = original
        self.onClose = onClose
        _name = State(initialValue: original.name)
        _role = State(initialValue: original.role ?? "")
        _personality = State(initialValue: "")
        _capabilitiesText = State(initialValue: "")
        _directives = State(initialValue: "")
        _status = State(initialValue: original.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetField("NAME") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                    }
                    sheetField("ROLE") {
                        TextField("Role", text: $role)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                    }
                    sheetField("PERSONALITY") {
                        TextEditor(text: $personality)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    sheetField("CAPABILITIES (comma-separated)") {
                        TextField("research, summarization", text: $capabilitiesText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                    }
                    sheetField("DIRECTIVES") {
                        TextEditor(text: $directives)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 80)
                    }
                    Text("Personality / capabilities / directives weren't in the summary fetch; leave blank to keep existing values.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))

                    fieldLabel("STATUS")
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton(
                        "SAVE CHANGES",
                        disabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                            || role.trimmingCharacters(in: .whitespaces).isEmpty
                            || submitting,
                        busy: submitting,
                        action: submit
                    )
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(false) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let r = role.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !r.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""

        let p = personality.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = directives.trimmingCharacters(in: .whitespacesAndNewlines)
        let capsRaw = capabilitiesText.trimmingCharacters(in: .whitespaces)
        let caps: [String]? = capsRaw.isEmpty
            ? nil
            : capabilitiesText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

        Task {
            do {
                let ok = try await NexusAPIClient.shared.updateAgent(
                    id: original.id,
                    name: n,
                    role: r,
                    personality: p.isEmpty ? nil : p,
                    capabilities: caps,
                    directives: d.isEmpty ? nil : d,
                    status: status
                )
                await MainActor.run {
                    submitting = false
                    if ok {
                        Haptics.success()
                        onClose(true)
                    } else {
                        Haptics.error()
                        error = "Update failed."
                    }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Generate Brief sheet (kind picker)

/// Asks Eve to produce a specific kind of brief for an operation. The
/// analyst call can take 30-60s, so we show a streaming-feel progress
/// indicator and disable dismissal mid-generation to avoid a "did it
/// work?" question. Server validates `kind` against the canonical set:
/// summary / actions / contradictions / themes / next-steps.
private struct GenerateBriefSheet: View {
    let operationId: String
    let onClose: (Bool) -> Void

    @State private var kind: String = "summary"
    @State private var generating: Bool = false
    @State private var error: String = ""
    @State private var lastContent: String = ""

    private let kinds = ["summary", "actions", "contradictions", "themes", "next-steps"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("BRIEF KIND")
                    Picker("Kind", selection: $kind) {
                        ForEach(kinds, id: \.self) { k in
                            Text(k.replacingOccurrences(of: "-", with: " ").capitalized).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(description(for: kind))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 4)

                    submitButton(
                        generating ? "EVE IS THINKING…" : "GENERATE BRIEF",
                        disabled: generating,
                        busy: generating,
                        action: generate
                    )
                    .padding(.top, 8)

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    if !lastContent.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PREVIEW · \(kind.uppercased())")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.indigo)
                            Text(lastContent)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.indigo.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer()
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Generate Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lastContent.isEmpty ? "Cancel" : "Done") {
                        onClose(!lastContent.isEmpty)
                    }
                    .disabled(generating)
                    .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func description(for kind: String) -> String {
        switch kind {
        case "summary":        return "Plain-language synthesis of every record on this operation."
        case "actions":        return "Concrete next steps — what should happen, who should do it."
        case "contradictions": return "Where the records disagree, or where evidence conflicts."
        case "themes":         return "Recurring patterns across the records — the underlying narrative."
        case "next-steps":     return "Sequenced plan for moving the operation forward this week."
        default:               return ""
        }
    }

    private func generate() {
        Haptics.heavy()
        generating = true
        error = ""
        Task {
            do {
                let brief = try await NexusAPIClient.shared.generateBrief(operationId: operationId, kind: kind)
                await MainActor.run {
                    generating = false
                    if let b = brief {
                        Haptics.success()
                        lastContent = b.content
                    } else {
                        Haptics.error()
                        error = "Eve returned empty output."
                    }
                }
            } catch let NexusAPIClient.APIError.requestFailed(msg) {
                await MainActor.run {
                    generating = false
                    Haptics.error()
                    error = msg
                }
            } catch {
                await MainActor.run {
                    generating = false
                    Haptics.error()
                    self.error = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Brain tab (Memory + Directives)

/// Eve's "brain config" — memories (ground-truth facts Eve cites in
/// answers) and directives (operator-defined rules that override default
/// behavior). Lumen exposes these as side-panel surfaces; iOS gets a
/// single tab with a segmented selector to switch between the two lists.
/// CRUD parity: list / add / activate-toggle / deactivate.
private struct BrainView: View {
    @State private var section: Section = .memories

    enum Section: String, CaseIterable, Identifiable {
        case memories, directives
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Group {
                switch section {
                case .memories:   EveMemoryListView()
                case .directives: EveDirectivesListView()
                }
            }
        }
    }
}

private struct EveMemoryListView: View {
    @State private var memories: [NexusAPIClient.EveMemory] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search: String = ""
    @State private var busy: Set<String> = []
    @State private var showAdd = false

    private var filtered: [NexusAPIClient.EveMemory] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return memories }
        return memories.filter { $0.content.lowercased().contains(q) || $0.type.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 20)
                    }
                    HStack {
                        Text("MEMORY BANK · \(filtered.count)\(search.isEmpty ? "" : " / \(memories.count)")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Button(action: { Haptics.light(); showAdd = true }) {
                            Label("NEW", systemImage: "plus.circle.fill")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if memories.isEmpty && !loading {
                        Text("Eve has no remembered facts yet. Tap + NEW to plant one.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 6) {
                        ForEach(filtered) { m in memoryRow(m) }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 36)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search memories")
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAdd) {
                AddMemorySheet { didAdd in
                    showAdd = false
                    if didAdd { Task { await load() } }
                }
            }
        }
    }

    private func memoryRow(_ m: NexusAPIClient.EveMemory) -> some View {
        let inFlight = busy.contains(m.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(m.type.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
                Text("· P\(m.priority)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.indigo.opacity(0.7))
                Spacer()
                if let src = m.source, !src.isEmpty {
                    Text(src)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                Button(action: { Task { await remove(m) } }) {
                    if inFlight {
                        ProgressView().controlSize(.small).tint(.red.opacity(0.7))
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            Text(m.content)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let m = try await NexusAPIClient.shared.fetchMemories()
            await MainActor.run { memories = m; loading = false }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                loading = false
            }
        }
    }

    private func remove(_ m: NexusAPIClient.EveMemory) async {
        Haptics.warning()
        await MainActor.run { busy.insert(m.id) }
        let ok = (try? await NexusAPIClient.shared.deleteMemory(id: m.id)) ?? false
        await MainActor.run {
            busy.remove(m.id)
            if ok {
                memories.removeAll { $0.id == m.id }
            }
        }
    }
}

private struct AddMemorySheet: View {
    let onClose: (Bool) -> Void
    @State private var type: String = "fact"
    @State private var content: String = ""
    @State private var priority: Int = 5
    @State private var submitting: Bool = false
    @State private var error: String = ""
    @FocusState private var contentFocused: Bool

    private let types = ["fact", "preference", "event", "reference", "directive"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("TYPE")
                    Picker("Type", selection: $type) {
                        ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    sheetField("CONTENT") {
                        TextEditor(text: $content)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 120)
                            .focused($contentFocused)
                    }

                    fieldLabel("PRIORITY · \(priority)")
                    Stepper(value: $priority, in: 0...10) {
                        Text("Higher = Eve weights more heavily")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton("ADD MEMORY",
                                 disabled: content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting,
                                 busy: submitting,
                                 action: submit)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(false) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { contentFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""
        Task {
            do {
                let ok = try await NexusAPIClient.shared.addMemory(type: type, content: c, priority: priority)
                await MainActor.run {
                    submitting = false
                    if ok { Haptics.success(); onClose(true) }
                    else  { Haptics.error(); error = "Save failed." }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct EveDirectivesListView: View {
    @State private var directives: [NexusAPIClient.EveDirective] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search: String = ""
    @State private var busy: Set<String> = []
    @State private var showAdd = false

    private var filtered: [NexusAPIClient.EveDirective] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return directives }
        return directives.filter {
            $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2).foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 20)
                    }
                    HStack {
                        Text("DIRECTIVES · \(filtered.count)\(search.isEmpty ? "" : " / \(directives.count)")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Button(action: { Haptics.light(); showAdd = true }) {
                            Label("NEW", systemImage: "plus.circle.fill")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if directives.isEmpty && !loading {
                        Text("No directives. Add one to override Eve's defaults.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 6) {
                        ForEach(filtered) { d in directiveRow(d) }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 36)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search directives")
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAdd) {
                AddDirectiveSheet { didAdd in
                    showAdd = false
                    if didAdd { Task { await load() } }
                }
            }
        }
    }

    private func directiveRow(_ d: NexusAPIClient.EveDirective) -> some View {
        let inFlight = busy.contains(d.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(d.type.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(d.type == "protocol" ? .orange.opacity(0.85) : .indigo.opacity(0.85))
                if let t = d.target, !t.isEmpty {
                    Text("· \(t)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Text("P\(d.priority)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                Toggle("", isOn: Binding(
                    get: { d.is_active },
                    set: { newVal in Task { await setActive(d, to: newVal) } }
                ))
                .labelsHidden()
                .tint(.green)
                .disabled(inFlight)
                Button(action: { Task { await remove(d) } }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            Text(d.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)
            Text(d.content)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(d.is_active ? 0.03 : 0.015))
        .opacity(d.is_active ? 1 : 0.55)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let d = try await NexusAPIClient.shared.fetchDirectives()
            await MainActor.run { directives = d; loading = false }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                loading = false
            }
        }
    }

    private func setActive(_ d: NexusAPIClient.EveDirective, to newVal: Bool) async {
        Haptics.tap()
        await MainActor.run { busy.insert(d.id) }
        let ok = (try? await NexusAPIClient.shared.setDirectiveActive(id: d.id, isActive: newVal)) ?? false
        await MainActor.run {
            busy.remove(d.id)
            if ok, let idx = directives.firstIndex(where: { $0.id == d.id }) {
                directives[idx] = NexusAPIClient.EveDirective(
                    id: d.id, type: d.type, title: d.title, content: d.content,
                    priority: d.priority, target: d.target, is_active: newVal,
                    created_at: d.created_at, updated_at: d.updated_at
                )
            }
        }
    }

    private func remove(_ d: NexusAPIClient.EveDirective) async {
        Haptics.warning()
        await MainActor.run { busy.insert(d.id) }
        let ok = (try? await NexusAPIClient.shared.deleteDirective(id: d.id)) ?? false
        await MainActor.run {
            busy.remove(d.id)
            if ok { directives.removeAll { $0.id == d.id } }
        }
    }
}

private struct AddDirectiveSheet: View {
    let onClose: (Bool) -> Void
    @State private var type: String = "directive"
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var priority: Int = 5
    @State private var target: String = "all"
    @State private var submitting: Bool = false
    @State private var error: String = ""
    @FocusState private var titleFocused: Bool

    private let types = ["directive", "protocol"]
    private let targets = ["all", "voice", "code", "research", "arena"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("TYPE")
                    Picker("Type", selection: $type) {
                        ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    sheetField("TITLE") {
                        TextField("e.g. Avoid the word 'absolutely'", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .focused($titleFocused)
                    }
                    sheetField("CONTENT") {
                        TextEditor(text: $content)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .frame(minHeight: 120)
                    }
                    fieldLabel("TARGET")
                    Picker("Target", selection: $target) {
                        ForEach(targets, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    fieldLabel("PRIORITY · \(priority)")
                    Stepper(value: $priority, in: 0...10) {
                        Text("Higher = Eve weights more heavily")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    submitButton("ADD DIRECTIVE",
                                 disabled: title.trimmingCharacters(in: .whitespaces).isEmpty
                                    || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || submitting,
                                 busy: submitting, action: submit)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("New Directive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose(false) }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { titleFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !c.isEmpty, !submitting else { return }
        Haptics.tap()
        submitting = true
        error = ""
        Task {
            do {
                let ok = try await NexusAPIClient.shared.addDirective(
                    type: type, title: t, content: c, priority: priority, target: target
                )
                await MainActor.run {
                    submitting = false
                    if ok { Haptics.success(); onClose(true) }
                    else  { Haptics.error(); error = "Save failed." }
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    Haptics.error()
                    self.error = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Global Search palette

/// Universal search reachable from any tab via the magnifying-glass icon
/// in the top bar. Searches conversations server-side (snippets) and
/// operations / agents / memories / schedules client-side from cached
/// lists. Groups results by source so the Director can scan to the right
/// section quickly. Tapping a row jumps to the relevant tab.
private struct GlobalSearchSheet: View {
    let onClose: () -> Void
    let onJumpToTab: (ContentView.Tab) -> Void

    @State private var query: String = ""
    @State private var convHits: [NexusAPIClient.ConversationSearchHit] = []
    @State private var opHits: [NexusAPIClient.OperationSummary] = []
    @State private var agentHits: [NexusAPIClient.AgentSummary] = []
    @State private var memoryHits: [NexusAPIClient.EveMemory] = []
    @State private var scheduleHits: [NexusAPIClient.ScheduleSummary] = []
    @State private var searching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    private var totalHits: Int {
        convHits.count + opHits.count + agentHits.count + memoryHits.count + scheduleHits.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.indigo)
                    TextField("Search everything…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, _ in scheduleSearch() }
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    if searching {
                        ProgressView().controlSize(.small).tint(.indigo)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 8)

                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    placeholder
                } else if totalHits == 0 && !searching {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            resultsGroup("CONVERSATIONS", count: convHits.count) {
                                ForEach(convHits) { hit in conversationRow(hit) }
                            }
                            resultsGroup("OPERATIONS", count: opHits.count) {
                                ForEach(opHits) { op in operationHitRow(op) }
                            }
                            resultsGroup("AGENTS", count: agentHits.count) {
                                ForEach(agentHits) { a in agentHitRow(a) }
                            }
                            resultsGroup("MEMORIES", count: memoryHits.count) {
                                ForEach(memoryHits) { m in memoryHitRow(m) }
                            }
                            resultsGroup("SCHEDULES", count: scheduleHits.count) {
                                ForEach(scheduleHits) { s in scheduleHitRow(s) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }.foregroundColor(.white.opacity(0.7))
                }
            }
            .onAppear { fieldFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.white.opacity(0.25))
            Text("Type 2+ characters to search")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            Text("conversations · operations · agents · memories · schedules")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 40)
            Image(systemName: "questionmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text("No matches for \"\(query)\"")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultsGroup<Content: View>(_ label: String, count: Int, @ViewBuilder _ rows: () -> Content) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(label) · \(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
                VStack(spacing: 5) { rows() }
            }
        }
    }

    private func conversationRow(_ hit: NexusAPIClient.ConversationSearchHit) -> some View {
        Button(action: { Haptics.light(); onJumpToTab(.voice); onClose() }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.85))
                    Text(hit.title).font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    Spacer()
                    Text(hit.source.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.5).foregroundColor(.white.opacity(0.4))
                }
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func operationHitRow(_ op: NexusAPIClient.OperationSummary) -> some View {
        Button(action: { Haptics.light(); onJumpToTab(.operations); onClose() }) {
            hitRow(icon: "square.stack.3d.up.fill", color: .indigo, title: op.name, subtitle: op.status.uppercased())
        }
        .buttonStyle(.plain)
    }

    private func agentHitRow(_ a: NexusAPIClient.AgentSummary) -> some View {
        Button(action: { Haptics.light(); onJumpToTab(.agents); onClose() }) {
            hitRow(icon: "person.fill", color: .green, title: a.name, subtitle: a.role ?? a.status.uppercased())
        }
        .buttonStyle(.plain)
    }

    private func memoryHitRow(_ m: NexusAPIClient.EveMemory) -> some View {
        Button(action: { Haptics.light(); onJumpToTab(.brain); onClose() }) {
            hitRow(icon: "brain.head.profile", color: .pink,
                   title: m.content, subtitle: "\(m.type.uppercased()) · P\(m.priority)")
        }
        .buttonStyle(.plain)
    }

    private func scheduleHitRow(_ s: NexusAPIClient.ScheduleSummary) -> some View {
        Button(action: { Haptics.light(); onJumpToTab(.schedules); onClose() }) {
            hitRow(icon: "calendar", color: .blue, title: s.name,
                   subtitle: "\(s.cron_expression) · \(s.target_type.uppercased())")
        }
        .buttonStyle(.plain)
    }

    private func hitRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Debounce the search so we don't fan out a request per keystroke.
    /// 250ms feels responsive without hammering the server when the user
    /// is mid-typing.
    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            convHits = []; opHits = []; agentHits = []; memoryHits = []; scheduleHits = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await runSearch(q: q)
        }
    }

    private func runSearch(q: String) async {
        await MainActor.run { searching = true }
        // Conversations: server-side fuzzy.
        async let conv = (try? await NexusAPIClient.shared.searchConversations(q: q)) ?? []
        // Other surfaces: client-side filter on cached list endpoints. Re-fetch
        // each time so results stay fresh (cheap — these are small payloads).
        async let ops = (try? await NexusAPIClient.shared.fetchOperations()) ?? []
        async let agents = (try? await NexusAPIClient.shared.fetchAgents()) ?? []
        async let mems = (try? await NexusAPIClient.shared.fetchMemories()) ?? []
        async let scheds = (try? await NexusAPIClient.shared.fetchSchedules()) ?? []

        let (c, o, a, m, s) = await (conv, ops, agents, mems, scheds)
        let qLower = q.lowercased()
        await MainActor.run {
            convHits = c
            opHits = o.filter {
                $0.name.lowercased().contains(qLower)
                    || ($0.description ?? "").lowercased().contains(qLower)
                    || $0.status.lowercased().contains(qLower)
            }
            agentHits = a.filter {
                $0.name.lowercased().contains(qLower)
                    || ($0.role ?? "").lowercased().contains(qLower)
            }
            memoryHits = m.filter {
                $0.content.lowercased().contains(qLower)
                    || $0.type.lowercased().contains(qLower)
            }
            scheduleHits = s.filter {
                $0.name.lowercased().contains(qLower)
                    || $0.cron_expression.lowercased().contains(qLower)
                    || $0.target_type.lowercased().contains(qLower)
            }
            searching = false
        }
    }
}

/// Button style that scales the label slightly while pressed. Makes
/// dashboard tiles feel like physical surfaces — they react under the
/// finger. Small effect (97% scale, 80ms ease) so it reads as feedback
/// rather than animation overhead.
struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Nexus Map graph (Canvas-rendered, matches Lumen's 3D map visual)

/// 2D port of Lumen's force-directed map. Layout: groups nodes by type
/// into concentric arcs around the center, then draws edges from
/// `MapEdge` data as luminous lines. Phone-sized so each cluster
/// occupies a wedge of the canvas, with edges crossing between clusters
/// to reveal the system's actual relationship topology.
///
/// Not animated/interactive force-sim — that's expensive on a phone and
/// the user value is "see the shape," not "play with it." Tap a node to
/// open its detail sheet (cross-tab pivot from there).
private struct NexusMapGraph: View {
    let nodes: [NexusAPIClient.MapNode]
    let allNodes: [NexusAPIClient.MapNode]
    let edges: [NexusAPIClient.MapEdge]
    let highlightedType: String?
    let onTapNode: (NexusAPIClient.MapNode) -> Void

    /// Cached node → position map computed from the canvas size.
    /// Recomputes on size or node-set change.
    @State private var positions: [String: CGPoint] = [:]
    @State private var canvasSize: CGSize = .zero

    private let typeOrder = ["operation", "agent", "record", "research", "topic", "directive", "human", "conversation"]

    private var visibleNodeIds: Set<String> {
        Set(nodes.map(\.id))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Subtle starfield-style background so the orbs glow
                // against something — pure black makes it feel empty.
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.04, blue: 0.10),
                        Color(red: 0.02, green: 0.02, blue: 0.05),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)

                // Edges layer
                Canvas { ctx, size in
                    for e in edges {
                        guard let p1 = positions[e.source],
                              let p2 = positions[e.target] else { continue }
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)
                        let color = edgeColor(for: e.type)
                        ctx.stroke(path, with: .color(color), lineWidth: 0.6)
                    }
                }

                // Nodes layer — interactive (Buttons over precise positions)
                ForEach(nodes) { node in
                    if let p = positions[node.id] {
                        nodeDot(node)
                            .position(p)
                    }
                }
            }
            .onAppear { recomputeLayout(in: geo.size) }
            .onChange(of: geo.size) { _, newSize in recomputeLayout(in: newSize) }
            .onChange(of: allNodes.count) { _, _ in recomputeLayout(in: geo.size) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nodeDot(_ node: NexusAPIClient.MapNode) -> some View {
        let color = NexusMapView.colorFor(node.type)
        let isHighlighted = highlightedType == nil || node.type == highlightedType
        let opacity = isHighlighted ? 1.0 : 0.25
        return Button(action: { onTapNode(node) }) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(color.opacity(0.25 * opacity))
                    .frame(width: 22, height: 22)
                    .blur(radius: 4)
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .opacity(opacity)
                Circle()
                    .stroke(Color.white.opacity(0.35 * opacity), lineWidth: 0.5)
                    .frame(width: 10, height: 10)
            }
        }
        .buttonStyle(.plain)
    }

    /// Compute hub-and-spoke layout: each type sits in a wedge around
    /// the center, with that type's nodes placed on a circular arc
    /// inside the wedge. Conversations (usually the noisiest cluster)
    /// get the outermost ring; operations/agents stay closer to center.
    private func recomputeLayout(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        canvasSize = size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Leave 24pt margin so glows don't clip
        let maxRadius = min(size.width, size.height) / 2 - 24

        // Group all nodes by type so layout is stable across filter changes —
        // hiding the topology would be misleading. Use allNodes for layout,
        // visibility only changes opacity (via highlightedType).
        var grouped: [String: [NexusAPIClient.MapNode]] = [:]
        for n in allNodes { grouped[n.type, default: []].append(n) }
        let types = typeOrder.filter { (grouped[$0]?.count ?? 0) > 0 }
        guard !types.isEmpty else { positions = [:]; return }

        // Each type gets a wedge of the circle. Distribute evenly.
        let wedgeAngle = (2 * .pi) / Double(types.count)
        var out: [String: CGPoint] = [:]

        // Assign each type a base radius — pull noisy types (conversations,
        // records) outward so they don't crowd the center.
        let radiusBy: [String: CGFloat] = [
            "operation": maxRadius * 0.45,
            "agent":     maxRadius * 0.50,
            "human":     maxRadius * 0.40,
            "directive": maxRadius * 0.55,
            "topic":     maxRadius * 0.65,
            "record":    maxRadius * 0.80,
            "research":  maxRadius * 0.75,
            "conversation": maxRadius * 0.92,
        ]

        for (i, t) in types.enumerated() {
            let mid = Double(i) * wedgeAngle - .pi / 2  // -π/2 = start at top
            let radius = radiusBy[t] ?? (maxRadius * 0.7)
            let typeNodes = grouped[t] ?? []
            let count = typeNodes.count
            // Spread nodes across roughly 80% of the wedge so adjacent
            // wedges don't bleed into each other.
            let spread = wedgeAngle * 0.8
            let start = mid - spread / 2
            for (j, node) in typeNodes.enumerated() {
                let t = count == 1 ? 0.5 : Double(j) / Double(count - 1)
                let angle = start + spread * t
                // Slight radial jitter so dense clusters don't perfectly
                // overlap. Stable per node id so layout doesn't dance
                // on re-render.
                let jitter = CGFloat(stableHash(node.id) % 12) - 6
                let r = radius + jitter
                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r
                out[node.id] = CGPoint(x: x, y: y)
            }
        }
        positions = out
    }

    /// Stable, non-cryptographic hash for layout jitter. Swift's default
    /// String.hashValue is randomized per launch which would cause the
    /// graph to "shuffle" on every cold start. This keeps it deterministic.
    private func stableHash(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        return abs(h)
    }

    private func edgeColor(for type: String) -> Color {
        switch type {
        case "topic-link":         return Color.orange.opacity(0.35)
        case "temporal":           return Color.white.opacity(0.12)
        case "record-belongs-to":  return Color.indigo.opacity(0.35)
        case "record-source":      return Color.blue.opacity(0.30)
        case "record-parent":      return Color.teal.opacity(0.35)
        case "research-on":        return Color.pink.opacity(0.40)
        case "research-producing": return Color.pink.opacity(0.25)
        default:                   return Color.white.opacity(0.15)
        }
    }
}

// MARK: - Team list sheet

/// Read-only view of the humans connected to this Nexus. Derived from
/// the `human`-type nodes the `/api/nexus-map` endpoint already returns
/// — there's no dedicated `/api/team/members` GET, but the map response
/// is the source of truth for "who is on Nexus." Management actions
/// (invite, setup, role change) deliberately route through the portal
/// for now — phone modals aren't the right surface for permissioning
/// decisions.
private struct TeamListSheet: View {
    let onClose: () -> Void

    @State private var members: [NexusAPIClient.MapNode] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if loading {
                        Text("LOADING…")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 20)
                    }
                    Text("MEMBERS · \(members.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if members.isEmpty && !loading {
                        Text("Just you so far. Invite team members from the portal.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 6) {
                        ForEach(members) { m in memberRow(m) }
                    }
                    .padding(.horizontal, 12)

                    Text("Add members or change roles from the web portal.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
                .padding(.bottom, 36)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func memberRow(_ m: NexusAPIClient.MapNode) -> some View {
        let statusColor: Color = {
            switch m.status {
            case "active":   return .green
            case "invited":  return .yellow
            case "inactive": return .gray
            default:         return .white.opacity(0.4)
            }
        }()
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.25)).frame(width: 36, height: 36)
                Text(initialOf(m.title))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                Text(m.subtitle.isEmpty ? "Member" : m.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            if let s = m.status {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(s.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(statusColor)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func initialOf(_ name: String) -> String {
        let first = name.first ?? "?"
        return String(first).uppercased()
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let map = try await NexusAPIClient.shared.fetchNexusMap()
            await MainActor.run {
                members = map.nodes.filter { $0.type == "human" }
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Load failed: \(error.localizedDescription)"
                loading = false
            }
        }
    }
}

#Preview {
    ContentView()
}
