// ConversationWindow.swift
//
// Per-conversation native window. Open via
//   openWindow(id: "conversation-detail", value: convId)
// Each window has its OWN message thread + send loop, completely independent
// of the main chat. The Director can have several conversations open at the
// same time and interact with each one.
//
// Routes through nexus-web /api/eve with the window's conversationId pinned,
// so server-side threading keeps each thread isolated.

import SwiftUI

struct ConversationWindow: View {
    let initialConversationId: String
    @EnvironmentObject var store: LumenStore

    // The thread this window is currently viewing. Starts at whatever id
    // the App opened the window with, but the in-window sidebar lets the
    // Director swap to any other thread without spawning a new window.
    @State private var conversationId: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var status: String = ""
    @State private var title: String = "Conversation"
    @FocusState private var inputFocused: Bool

    /// Sidebar visibility — Director can collapse to maximize the message
    /// area, or expand to browse + switch threads. Defaults to visible
    /// because the #1 ask for pop-out was "show me my conversations."
    @State private var sidebarVisible: Bool = true

    /// Composer expansion. Defaults to false — chat input must NEVER eat
    /// half the window. Tapping the expand chevron flips to a taller mode
    /// that grows upward into the message area for paragraph composition.
    @State private var composerExpanded: Bool = false

    // Compact: ~3 lines, fits a sentence comfortably without dominating
    // the window. Expanded: up to ~12 lines, paragraph-friendly.
    private var composerMaxHeight: CGFloat { composerExpanded ? 240 : 88 }

    init(conversationId: String) {
        self.initialConversationId = conversationId
        self._conversationId = State(initialValue: conversationId)
    }

    var body: some View {
        ZStack {
            BackgroundLayer()
            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebar
                        .frame(width: 200)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().background(Color.secondary.opacity(0.18))
                }
                VStack(spacing: 0) {
                    header
                    messageList
                    inputBar
                }
            }
        }
        .task(id: conversationId) {
            // Re-runs whenever the user clicks a different thread in the
            // sidebar. Also runs once on first appear.
            store.registerActiveConversation(id: conversationId, title: title)
            await loadHistory()
            store.registerActiveConversation(id: conversationId, title: title)
        }
    }

    // ── Sidebar ───────────────────────────────────────────────────────────
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("THREADS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.secondary.opacity(0.75))
                Spacer()
                Text("\(store.conversations.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.12)), alignment: .bottom)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.conversations) { conv in
                        sidebarRow(conv)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.secondary.opacity(0.04))
    }

    @ViewBuilder
    private func sidebarRow(_ conv: ConversationSummary) -> some View {
        let isActive = conv.id == conversationId
        Button(action: { switchTo(conv) }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? C.eve : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title.isEmpty ? "Untitled" : conv.title)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .foregroundColor(.primary.opacity(isActive ? 1.0 : 0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !conv.source.isEmpty {
                        Text(conv.source.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? C.eve.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func switchTo(_ conv: ConversationSummary) {
        guard conv.id != conversationId else { return }
        // Clear visible state immediately so the user sees the swap, then
        // the .task(id:) re-runs and pulls history.
        title = conv.title
        messages = []
        loading = true
        conversationId = conv.id
    }

    // ── Header ────────────────────────────────────────────────────────────
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { withAnimation(.easeOut(duration: 0.18)) { sidebarVisible.toggle() } }) {
                Image(systemName: sidebarVisible ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(sidebarVisible ? C.eve : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(sidebarVisible ? 0.0 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help(sidebarVisible ? "Hide thread list" : "Show thread list")

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 12))
                .foregroundColor(C.eve)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(1)
            Text("· \(messages.count) messages")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            if loading || sending {
                ProgressView().controlSize(.mini).tint(C.eve)
            }
            Button(action: { Task { await loadHistory() } }) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh thread")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.15)), alignment: .bottom)
    }

    // ── Messages ──────────────────────────────────────────────────────────
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty && !loading {
                        emptyState
                    }
                    ForEach(messages) { m in
                        ConvWindowMessageRow(message: m).id(m.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No messages in this thread yet.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // ── Input ─────────────────────────────────────────────────────────────
    private var inputBar: some View {
        let claimed = (store.voiceClaimedBy == conversationId)
        let claimedElsewhere = (store.voiceClaimedBy != nil && !claimed)
        return HStack(spacing: 10) {
            // Mic — claims voice for THIS window's conversation
            Button(action: toggleVoiceClaim) {
                ZStack {
                    Circle().fill(claimed ? C.listen.opacity(0.18) : Color.secondary.opacity(0.08))
                    Circle().stroke(claimed ? C.listen.opacity(0.5) : Color.secondary.opacity(0.18), lineWidth: 1)
                    Image(systemName: claimed ? "mic.fill" : "mic")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(claimed ? C.listen : (claimedElsewhere ? .secondary.opacity(0.3) : .secondary.opacity(0.7)))
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(claimedElsewhere)
            .help(
                claimed ? "Voice mode active in THIS window — tap to stop"
                : claimedElsewhere ? "Voice mode is active in another window"
                : "Start voice mode for this conversation"
            )

            // Mute — visible only when this window owns voice
            if claimed {
                Button(action: { store.toggleUserMute() }) {
                    let muted = store.userMuted
                    ZStack {
                        Circle().fill(muted ? C.danger.opacity(0.18) : Color.secondary.opacity(0.08))
                        Circle().stroke(muted ? C.danger.opacity(0.5) : Color.secondary.opacity(0.18), lineWidth: 1)
                        Image(systemName: muted ? "mic.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(muted ? C.danger : .secondary.opacity(0.6))
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(store.userMuted ? "Muted — tap to unmute" : "Mute (let Eve finish without interrupt)")
                .transition(.opacity.combined(with: .scale))
            }

            ZStack(alignment: .topTrailing) {
                ChatComposerField(
                    text: $input,
                    placeholder: "Send to this thread…  (⇧↩ for newline)",
                    minHeight: 22,
                    maxHeight: composerMaxHeight,
                    fontSize: 13,
                    onSubmit: { Task { await submit() } }
                )
                .frame(minHeight: 22)
                .padding(8)
                .padding(.trailing, 22) // leave room for the expand chevron
                .background(Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(action: { withAnimation(.easeOut(duration: 0.14)) { composerExpanded.toggle() } }) {
                    Image(systemName: composerExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 4)
                .help(composerExpanded ? "Minimize composer" : "Expand composer for longer messages")
            }

            Button(action: { Task { await submit() } }) {
                Image(systemName: sending ? "hourglass" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(input.trimmingCharacters(in: .whitespaces).isEmpty || sending ? Color.secondary.opacity(0.4) : C.eve)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.15)), alignment: .top)
    }

    /// Claim or release the voice mic for THIS window's conversation. When
    /// claimed, transcripts coming out of EveVoiceManager get routed to
    /// `submit(_:)` so they land in this window's thread (and use this
    /// window's conversationId).
    private func toggleVoiceClaim() {
        if store.voiceClaimedBy == conversationId {
            store.stopListening()
        } else {
            // Acquire — transcripts feed THIS window's submit
            store.startVoiceFor(claimId: conversationId) { text in
                Task { await submit(voiceText: text) }
            }
        }
    }

    // ── Data ──────────────────────────────────────────────────────────────
    private func loadHistory() async {
        loading = true
        defer { loading = false }
        let base = LumenAPIManager.shared.nexusBase
        guard var comps = URLComponents(string: "\(base)/api/eve/history") else { return }
        comps.queryItems = [URLQueryItem(name: "conversationId", value: conversationId)]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let raw = json["messages"] as? [[String: Any]] ?? []
            let parsed: [ChatMessage] = raw.compactMap { m in
                guard let role = m["role"] as? String, let content = m["content"] as? String else { return nil }
                return ChatMessage(role: role == "user" ? .user : .assistant, content: content)
            }
            messages = parsed

            // Pull the conversation's title for the window header
            let conv = store.conversations.first { $0.id == conversationId }
            title = conv?.title ?? title
        } catch {
            status = "Could not load thread: \(error.localizedDescription)"
        }
    }

    private func submit(voiceText: String? = nil) async {
        let raw = voiceText ?? input
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !sending else { return }
        if voiceText == nil { input = "" }
        messages.append(ChatMessage(role: .user, content: text))
        sending = true
        defer { sending = false }

        do {
            let result = try await LumenAPIManager.shared.callNexusEve(
                message: text,
                conversationId: conversationId,
                history: ArraySlice(messages.dropLast())
            )
            var msg = ChatMessage(role: .assistant, content: result.content, brain: "grok")
            msg.toolCalls = result.toolCalls
            messages.append(msg)
            status = ""
            // Speak the reply through the shared voice manager so the
            // popout-window experience matches the main thread (audio still
            // routes through the user's speakers regardless of which window
            // claimed voice).
            if store.voiceClaimedBy == conversationId {
                store.voice.speak(result.content) {}
            }
        } catch {
            messages.append(ChatMessage(role: .assistant, content: "Couldn't reach Nexus."))
            status = "Send failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Message bubble

private struct ConvWindowMessageRow: View {
    let message: ChatMessage
    @EnvironmentObject var store: LumenStore
    private var isEve: Bool { message.role == .assistant }

    /// Compact tool-call card matching Lumen's main-thread style. Renders inline
    /// with the message body in the per-conversation pop-out window.
    @ViewBuilder
    private func toolCallRow(_ tc: ToolCallSummary) -> some View {
        let accent: Color = !tc.success ? C.danger
            : (tc.name.hasPrefix("arena_payment") ? C.danger
            : (tc.name.hasPrefix("arena_sync") ? C.eve
            : (tc.name.hasPrefix("arena_task") ? C.listen : C.eve)))
        HStack(spacing: 8) {
            Image(systemName: tc.success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(tc.humanLabel.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(accent)
                Text(tc.primary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(1)
                if !tc.detail.isEmpty {
                    Text(tc.detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(accent.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isEve {
                Text("EVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(C.eve.opacity(0.85))
                    .frame(width: 32, alignment: .leading)
                    .padding(.top, 8)
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Tool-call action chips above prose so Eve's actions are visible
                // here too — same as the main thread.
                if isEve, !message.toolCalls.isEmpty {
                    ForEach(message.toolCalls) { tc in
                        toolCallRow(tc)
                    }
                }
                if isEve {
                    Text(MentionRenderer.attributedRich(message.content))
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .environment(\.openURL, OpenURLAction { url in
                            if MentionRenderer.handle(url: url) { return .handled }
                            return .systemAction
                        })
                } else {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isEve ? C.eve.opacity(0.10) : Color.secondary.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke((isEve ? C.eve : .secondary).opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: isEve ? .leading : .trailing)
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
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(message.content, forType: .string)
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
            }

            if !isEve {
                Text("YOU")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                    .padding(.top, 8)
            } else {
                Spacer(minLength: 60)
            }
        }
    }
}
