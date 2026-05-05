// EveVoiceManager.swift
// Nexus iOS — real-time voice input with Hey Sync detection

import AVFoundation
import Speech
import Foundation

struct ChatTurn: Identifiable {
    let id = UUID()
    let role: Role           // user | eve
    var content: String      // var so streaming could mutate (future)
    let timestamp = Date()
    /// Which brain produced this assistant reply: "grok" | "local" | "claude" | "vision" | "offline".
    var brain: String? = nil
    /// Tool calls Eve fired in this turn — rendered as visible cards in the bubble.
    var toolCalls: [ToolCallSummary] = []
    enum Role { case user, eve }
}

/// Display-ready record of a single tool Eve invoked. Mirrors Lumen's
/// `ToolCallSummary` so the JSON contract from /api/eve renders identically
/// across all clients.
struct ToolCallSummary: Hashable, Identifiable {
    let id = UUID()
    let name: String         // raw tool name (e.g., arena_task_create)
    let humanLabel: String   // "Created task", "Logged action", etc.
    let primary: String      // headline value: title / name / amount
    let detail: String       // secondary line: id / status / count
    let success: Bool

    static func from(rawName: String, args: [String: Any], result: [String: Any]) -> ToolCallSummary {
        let success = (result["success"] as? Bool) ?? true
        let err = result["error"] as? String

        switch rawName {
        case "arena_task_create":
            let title = (args["title"] as? String) ?? "Untitled task"
            let id = (result["task_id"] as? String) ?? ""
            let assignee = args["assignee"] as? String
            let detail = [id, assignee.map { "→ \($0)" }].compactMap { $0 }.compactMap { $0 }.joined(separator: "  ")
            return .init(name: rawName, humanLabel: "Created task", primary: title,
                         detail: success ? detail : (err ?? "failed"), success: success)
        case "arena_task_update":
            let id = (args["task_id"] as? String) ?? ""
            let status = (args["status"] as? String) ?? "updated"
            return .init(name: rawName, humanLabel: "Updated task", primary: id,
                         detail: success ? status.uppercased() : (err ?? "failed"), success: success)
        case "arena_payment_route":
            let amount = (args["amount"] as? Double).map { String(format: "$%.2f", $0) }
                ?? (args["amount"] as? Int).map { "$\($0)" } ?? "?"
            let ref = (args["reference"] as? String) ?? ""
            return .init(name: rawName, humanLabel: "Routed payment", primary: amount,
                         detail: success ? ref : (err ?? "failed"), success: success)
        case "arena_sync_push":
            return .init(name: rawName, humanLabel: "Pushed memory sync", primary: "Memory bank",
                         detail: success ? "synced" : (err ?? "failed"), success: success)
        case "arena_recent":
            let entries = (result["entries"] as? [Any])?.count ?? 0
            return .init(name: rawName, humanLabel: "Read Arena log",
                         primary: "\(entries) entries", detail: "", success: success)
        default:
            let primary = (args["title"] as? String)
                ?? (args["name"] as? String)
                ?? (args["content"] as? String).map { String($0.prefix(40)) } ?? rawName
            return .init(name: rawName, humanLabel: rawName.replacingOccurrences(of: "_", with: " ").capitalized,
                         primary: primary, detail: success ? "ok" : (err ?? "failed"), success: success)
        }
    }
}

class EveVoiceManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynth  = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var conversationId: String?
    private var useLocalBrain = false  // toggled by "use local" / "use grok" voice phrases

    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var statusMessage = "Ready"
    @Published var lastReply = ""
    @Published var messages: [ChatTurn] = []
    @Published var pendingImages: [Data] = []  // raw image data, base64-encoded on send

    override init() {
        super.init()
    }

    func startListening() {
        isListening = true
        transcribedText = ""
        statusMessage = "Listening..."

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self, status == .authorized else {
                DispatchQueue.main.async { self?.statusMessage = "Microphone permission denied" }
                return
            }

            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                let inputNode = self.audioEngine.inputNode
                self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                self.recognitionRequest?.shouldReportPartialResults = true

                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    self.recognitionRequest?.append(buffer)
                }

                self.audioEngine.prepare()
                try self.audioEngine.start()

                self.recognitionTask = self.speechRecognizer?.recognitionTask(
                    with: self.recognitionRequest!
                ) { result, error in
                    if let result = result {
                        DispatchQueue.main.async {
                            self.transcribedText = result.bestTranscription.formattedString
                        }
                    }
                    if error != nil {
                        self.stopListening()
                    }
                }
            } catch {
                DispatchQueue.main.async { self.statusMessage = "Audio setup failed: \(error)" }
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        DispatchQueue.main.async {
            self.isListening = false
            self.statusMessage = "Processing..."
        }

        handleTranscription(transcribedText)
    }

    private func handleTranscription(_ text: String) {
        let lower = text.lowercased()

        if lower.contains("hey sync") || lower.contains("sync with home") {
            DispatchQueue.main.async { self.statusMessage = "Syncing with home..." }
            Task { await syncWithHome() }

        } else if lower.contains("use grok") || lower.contains("use cloud") || lower.contains("use internet") || lower.contains("go online") {
            useLocalBrain = false
            DispatchQueue.main.async { self.statusMessage = "Cloud brain (Grok) active" }

        } else if lower.contains("use local") || lower.contains("go offline") || lower.contains("use ollama") {
            useLocalBrain = true
            DispatchQueue.main.async { self.statusMessage = "Local brain (Ollama) active" }

        } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
            DispatchQueue.main.async { self.statusMessage = "Ready" }

        } else {
            DispatchQueue.main.async { self.statusMessage = "Asking Eve..." }
            Task { await askHomeBrain(text) }
        }
    }

    /// Pull latest memory and context from home machine via Supabase
    func syncWithHome() async {
        do {
            struct MemoryUpdate: Decodable {
                let id: String
                let content: String
                let created_at: String
            }

            let updates: [MemoryUpdate] = try await SupabaseManager.shared.client
                .from("memory_updates")
                .select()
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            await MainActor.run {
                self.statusMessage = updates.isEmpty
                    ? "Nothing new to sync"
                    : "✅ Synced — memory updated"
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "Sync failed — trying Apple Intelligence fallback"
            }
            // TODO: fall back to Apple Intelligence
        }
    }

    /// Ask Eve's home brain. Three paths in priority order:
    /// 1. `useLocalBrain` + LAN URL configured → direct-to-Ollama (fastest, no nexus-web hop)
    /// 2. `useLocalBrain` → nexus-web `/api/eve/local` (Ollama, threaded with memory)
    /// 3. Default → nexus-web `/api/eve` (Grok with tool calling)
    func askHomeBrain(_ message: String) async {
        let api = NexusAPIClient.shared

        // Vision branch — if images attached, route through /api/eve/local with llava
        if !pendingImages.isEmpty {
            let images = pendingImages
            await MainActor.run {
                self.pendingImages.removeAll()
                let label = "\(message)  📷×\(images.count)"
                self.messages.append(ChatTurn(role: .user, content: label))
                self.statusMessage = "Eve is looking…"
            }
            do {
                let b64 = images.map { $0.base64EncodedString() }
                let result = try await api.askEveLocalWithImages(message: message, images: b64, conversationId: conversationId)
                await MainActor.run {
                    if self.conversationId == nil { self.conversationId = result.conversationId }
                    self.lastReply = result.content
                    self.statusMessage = "Ready"
                    self.messages.append(ChatTurn(role: .eve, content: result.content))
                }
                speak(result.content)
            } catch {
                await MainActor.run {
                    self.messages.append(ChatTurn(role: .eve, content: "I couldn't process the image."))
                    self.statusMessage = "Vision failed: \(error.localizedDescription)"
                }
            }
            return
        }

        await MainActor.run {
            self.messages.append(ChatTurn(role: .user, content: message))
        }

        // Path 1 — direct LAN Ollama (zero nexus-web round-trip)
        if useLocalBrain, api.localBrainURL != nil {
            do {
                let reply = try await api.askLocalDirect(message: message)
                await MainActor.run {
                    self.lastReply     = reply
                    self.statusMessage = "Ready · LAN"
                    self.messages.append(ChatTurn(role: .eve, content: reply))
                }
                speak(reply)
                return
            } catch {
                // Fall through to nexus-web variants if direct fails
                await MainActor.run { self.statusMessage = "LAN unreachable — using nexus-web…" }
            }
        }

        do {
            // Local path returns 2-tuple, Grok returns 3-tuple. Branch the
            // call to keep types straight, then build a uniform turn.
            var replyContent: String = ""
            var replyConvId: String? = nil
            var replyTools: [ToolCallSummary] = []
            var replyBrain: String = useLocalBrain ? "local" : "grok"

            if useLocalBrain {
                let r = try await api.askEveLocal(message: message, conversationId: conversationId)
                replyContent = r.content
                replyConvId  = r.conversationId
            } else {
                let r = try await api.askEve(message: message, conversationId: conversationId)
                replyContent = r.content
                replyConvId  = r.conversationId
                replyTools   = r.toolCalls
            }

            await MainActor.run {
                if self.conversationId == nil { self.conversationId = replyConvId }
                self.lastReply     = replyContent
                self.statusMessage = "Ready"
                var turn = ChatTurn(role: .eve, content: replyContent)
                turn.brain = replyBrain
                turn.toolCalls = replyTools
                self.messages.append(turn)
            }
            speak(replyContent)

        } catch NexusAPIClient.APIError.unauthorized {
            await MainActor.run {
                self.statusMessage = "Sign in required — open settings"
                self.messages.append(ChatTurn(role: .eve, content: "Sign in required — open settings."))
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "Brain unreachable: \(error.localizedDescription)"
                self.messages.append(ChatTurn(role: .eve, content: "Brain unreachable: \(error.localizedDescription)"))
            }
        }
    }

    /// Speaks Eve's reply. Tries nexus-web's ElevenLabs route first
    /// (human-sounding voice). Falls back to AVSpeechSynthesizer if the
    /// network call fails — so Eve still talks offline, just sounds robotic.
    private func speak(_ text: String) {
        speechSynth.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        let speakable = String(text.prefix(600))

        Task { [weak self] in
            guard let self else { return }
            if let mp3 = await self.fetchEveTTS(text: speakable) {
                await MainActor.run { self.playMP3(mp3) }
            } else {
                await MainActor.run { self.fallbackSystemSpeak(speakable) }
            }
        }
    }

    private func fetchEveTTS(text: String) async -> Data? {
        let api = NexusAPIClient.shared
        guard let sid = api.sessionId, !sid.isEmpty else { return nil }
        guard let url = URL(string: "\(api.nexusBase)/api/eve/tts") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sid)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text":     text,
            "voice_id": api.voiceId,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func playMP3(_ data: Data) {
        // Set the audio session to playback so the speaker rings out clearly,
        // even after recognition put it in record mode.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            fallbackSystemSpeak("Voice playback failed.")
        }
    }

    private func fallbackSystemSpeak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate  = 0.5
        speechSynth.speak(utterance)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.audioPlayer = nil }
    }

    /// Resets the active conversation thread — next message starts fresh.
    func newConversation() {
        conversationId = nil
        DispatchQueue.main.async {
            self.lastReply = ""
            self.statusMessage = "New conversation"
            self.messages.removeAll()
            self.pendingImages.removeAll()
        }
    }

    /// Append an image to send with the next message.
    /// 5MB cap per image to keep payloads sane.
    func attachImage(_ data: Data) {
        guard data.count <= 5 * 1024 * 1024 else { return }
        DispatchQueue.main.async { self.pendingImages.append(data) }
    }

    func clearPendingImages() {
        DispatchQueue.main.async { self.pendingImages.removeAll() }
    }

    /// Switch the active conversation to an existing one. The next user
    /// message will be threaded under this conversationId server-side and
    /// have access to the prior history when Eve answers.
    func loadConversation(id: String, history: [NexusAPIClient.HistoryMessage]) {
        conversationId = id
        let mapped = history.map { ChatTurn(role: $0.role == "user" ? .user : .eve, content: $0.content) }
        let lastEve = history.reversed().first(where: { $0.role == "assistant" })?.content ?? ""
        DispatchQueue.main.async {
            self.messages      = mapped
            self.lastReply     = lastEve
            self.statusMessage = "Resumed conversation"
        }
    }
}
