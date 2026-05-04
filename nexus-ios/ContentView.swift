// ContentView.swift
// Nexus iOS — main voice interface

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var voice = EveVoiceManager()
    @State private var sessionId: String? = NexusAPIClient.shared.sessionId
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var tab: Tab = .voice

    enum Tab { case voice, control }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if sessionId == nil {
                PinAuthView { sid in sessionId = sid }
            } else {
                authenticatedView
            }
        }
        .animation(.easeInOut, value: sessionId)
        .sheet(isPresented: $showSettings) {
            SettingsView(onLogout: {
                NexusAPIClient.shared.logout()
                sessionId = nil
                showSettings = false
            })
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(onLoad: { id, history in
                voice.loadConversation(id: id, history: history)
                showHistory = false
            })
        }
    }

    private var authenticatedView: some View {
        VStack(spacing: 0) {
            // Top bar: tab switch + settings
            HStack(spacing: 16) {
                tabButton("VOICE", .voice)
                tabButton("CONTROL", .control)
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)

            switch tab {
            case .voice:   mainView
            case .control: ControlPanel()
            }
        }
    }

    private func voiceOrSend() {
        if !voice.pendingImages.isEmpty {
            // Vision-only request: no transcribed text needed
            Task { await voice.askHomeBrain("") }
            return
        }
        if voice.isListening { voice.stopListening() } else { voice.startListening() }
    }

    private func tabButton(_ label: String, _ value: Tab) -> some View {
        Button(action: { tab = value }) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundColor(tab == value ? .indigo : .gray)
        }
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

                Button(action: voiceOrSend) {
                    Text(voice.isListening ? "Done" : (voice.pendingImages.isEmpty ? "Talk to Eve" : "Ask Eve"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(voice.isListening ? Color.red.opacity(0.8) : Color.indigo)
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
            .animation(.easeInOut(duration: 0.2), value: voice.pendingImages.count)
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
    @State private var digits: [String] = Array(repeating: "", count: 4)
    @State private var error: String = ""
    @State private var loading = false
    @FocusState private var focusedIndex: Int?

    var body: some View {
        VStack(spacing: 36) {
            Spacer()
            Text("NEXUS")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.indigo)
                .tracking(8)

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

            Spacer()
        }
        .onAppear { focusedIndex = 0 }
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
        loading = true
        defer { loading = false }
        let pin = digits.joined()
        do {
            let sid = try await NexusAPIClient.shared.authenticate(pin: pin)
            await MainActor.run { onAuth(sid) }
        } catch {
            await MainActor.run {
                self.error = "Invalid PIN"
                self.digits = Array(repeating: "", count: 4)
                self.focusedIndex = 0
            }
        }
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

            Text(turn.content)
                .font(.system(size: 13))
                .foregroundColor(isEve ? .indigo.opacity(0.92) : .white.opacity(0.78))
                .multilineTextAlignment(.leading)
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
                .textSelection(.enabled)

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

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading conversations…")
                } else if conversations.isEmpty {
                    Text(status.isEmpty ? "No conversations yet." : status)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(conversations) { c in
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

#Preview {
    ContentView()
}
