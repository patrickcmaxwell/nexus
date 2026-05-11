// ContentView.swift
// Nexus iOS — main voice interface

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var voice = EveVoiceManager()
    @State private var sessionId: String? = NexusAPIClient.shared.sessionId
    @State private var activeProfile: NexusAPIClient.ActiveProfile? = nil
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showCommandCenter = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var tab: Tab = .voice
    @State private var composeText: String = ""
    /// True until the user passes the biometric gate on launch (only set
    /// when biometrics are enabled AND there's a cached session). When
    /// true, we hide the authenticated UI behind a Face ID prompt.
    @State private var biometricsLocked: Bool = EveBiometrics.shared.shouldUnlockOnLaunch
    @FocusState private var composeFocused: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case voice, operations, agents, schedules, terminals, briefing, arena
        var id: String { rawValue }
        var label: String {
            switch self {
            case .voice:      return "EVE"
            case .operations: return "OPS"
            case .agents:     return "AGENTS"
            case .schedules:  return "SCHED"
            case .terminals:  return "TERM"
            case .briefing:   return "BRIEF"
            case .arena:      return "ARENA"
            }
        }
        var icon: String {
            switch self {
            case .voice:      return "waveform"
            case .operations: return "square.stack.3d.up"
            case .agents:     return "person.2"
            case .schedules:  return "calendar"
            case .terminals:  return "terminal"
            case .briefing:   return "newspaper"
            case .arena:      return "list.bullet.rectangle"
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
                    case .voice:      mainView
                    case .operations: OperationsListView()
                    case .agents:     AgentsListView()
                    case .schedules:  SchedulesListView()
                    case .terminals:  TerminalsListView()
                    case .briefing:   BriefingView()
                    case .arena:      ArenaLogView()
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
                    Button("Save") {
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

                        dismiss()
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { onLogout() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if loading {
                    Text("LOADING…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray).tracking(2)
                        .padding(.top, 24)
                } else if entries.isEmpty {
                    Text(errorText.isEmpty ? "Eve hasn't fired any tools yet." : errorText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 24)
                } else {
                    ForEach(entries) { e in
                        ArenaEntryRow(entry: e)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await load() }
        .task { await load() }
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
                    Text("OPERATIONS · \(operations.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        ForEach(operations) { op in
                            NavigationLink(value: op) { OperationListRow(op: op) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .refreshable { await refresh() }
            .navigationDestination(for: NexusAPIClient.OperationSummary.self) { op in
                OperationDetailView(operation: op)
            }
        }
        .task {
            await refresh()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if Task.isCancelled { break }
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
                        statusPill(operation.status)
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

                // Records
                section("RECORDS · \(records.count)") {
                    if records.isEmpty {
                        Text("No records yet.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 16)
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
        VStack(alignment: .leading, spacing: 4) {
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
        Task {
            await MainActor.run { cycling = true }
            let next: String
            switch operation.status {
            case "planning": next = "active"
            case "active":   next = "paused"
            case "paused":   next = "active"
            case "complete": next = "planning"
            default:         next = "planning"
            }
            _ = try? await NexusAPIClient.shared.setOperationStatus(id: operation.id, status: next)
            await MainActor.run { cycling = false }
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
                    Text("AGENTS · \(agents.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        ForEach(agents) { a in
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
            .refreshable { await refresh() }
            .navigationDestination(for: NexusAPIClient.AgentSummary.self) { a in
                AgentDetailView(agent: a)
            }
        }
        .task {
            await refresh()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if Task.isCancelled { break }
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

    private var statusColor: Color {
        switch agent.status { case "active": return .green; case "standby": return .yellow; default: return .gray }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        Text(agent.status.uppercased())
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

                HStack(spacing: 8) {
                    Button(action: runNow) {
                        Label(running ? "Running…" : "Run Now", systemImage: "bolt.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.indigo.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .disabled(running || agent.status != "active")
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
        .task { await load() }
        .refreshable { await load() }
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
        Task {
            await MainActor.run { running = true }
            _ = try? await NexusAPIClient.shared.runAgent(id: agent.id)
            await MainActor.run { running = false }
            await load()
        }
    }
}

// MARK: - Schedules

private struct SchedulesListView: View {
    @State private var schedules: [NexusAPIClient.ScheduleSummary] = []
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
                Text("SCHEDULES · \(schedules.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if schedules.isEmpty && !loading {
                    Text("No schedules yet. Create one in the portal.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                VStack(spacing: 6) {
                    ForEach(schedules) { s in scheduleRow(s) }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func scheduleRow(_ s: NexusAPIClient.ScheduleSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(s.enabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(s.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let s = try await NexusAPIClient.shared.fetchSchedules()
            await MainActor.run {
                self.schedules = s
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

#Preview {
    ContentView()
}
