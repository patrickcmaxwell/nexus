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
    let conversationId: String
    @EnvironmentObject var store: LumenStore
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var status: String = ""
    @State private var title: String = "Conversation"
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            BackgroundLayer()
            VStack(spacing: 0) {
                header
                messageList
                inputBar
            }
        }
        .task { await loadHistory() }
    }

    // ── Header ────────────────────────────────────────────────────────────
    private var header: some View {
        HStack(spacing: 10) {
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
        HStack(spacing: 10) {
            TextField("Send to this thread…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { Task { await submit() } }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(inputFocused ? C.eve.opacity(0.4) : Color.secondary.opacity(0.18), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

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

    private func submit() async {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !sending else { return }
        input = ""
        messages.append(ChatMessage(role: .user, content: text))
        sending = true
        defer { sending = false }

        do {
            let result = try await LumenAPIManager.shared.callNexusEve(
                message: text,
                conversationId: conversationId,
                history: ArraySlice(messages.dropLast())
            )
            messages.append(ChatMessage(role: .assistant, content: result.content))
            status = ""
        } catch {
            messages.append(ChatMessage(role: .assistant, content: "Couldn't reach Nexus."))
            status = "Send failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Message bubble

private struct ConvWindowMessageRow: View {
    let message: ChatMessage
    private var isEve: Bool { message.role == .assistant }

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

            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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
