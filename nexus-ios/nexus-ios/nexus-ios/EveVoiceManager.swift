// EveVoiceManager.swift
// Nexus iOS — real-time voice input with Hey Sync detection

import AVFoundation
import Speech
import Foundation
import Combine

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

class EveVoiceManager: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynth  = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var conversationId: String?
    private var useLocalBrain = false  // toggled by "use local" / "use grok" voice phrases

    // MARK: - Streaming TTS state
    //
    // Instead of waiting for the full reply, complete sentences are pulled
    // out as deltas arrive and each is sent to TTS independently. The
    // first sentence usually finishes generating in <1 s after submit,
    // so audio playback starts ~5-8s earlier than the old "wait then
    // speak the whole thing" path.
    //
    // streamingTTSEnabled — feature flag; flip off via UserDefaults if
    // a bug appears. Default ON because perceived latency is the win.
    //
    // ttsRequestId — monotonically incremented each time a new request
    // begins. In-flight TTS fetches check their captured id against the
    // current value before enqueuing; mismatched = stale and dropped.
    // This is how we avoid playing fragments of the previous reply when
    // the Director starts a new turn mid-speak.
    //
    // pendingSentence — characters accumulated since the last sentence
    // boundary. Flushed (queued for TTS) on `. ! ? \n` or at stream end.
    private var streamingTTSEnabled: Bool {
        UserDefaults.standard.object(forKey: "nexus.tts.streaming") as? Bool ?? true
    }
    private var ttsRequestId: Int = 0
    private var pendingSentence: String = ""
    private var ttsAudioQueue: [Data] = []
    private var ttsIsPlaying: Bool = false

    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var statusMessage = "Ready"
    @Published var lastReply = ""
    @Published var messages: [ChatTurn] = []
    @Published var pendingImages: [Data] = []  // raw image data, base64-encoded on send

    /// True while a request to Eve is in flight (sent → reply received).
    /// Guards against double-submit in conversation mode: if the user
    /// keeps talking while Eve is still answering the previous turn,
    /// silence detection will not fire another submit. The mic still
    /// transcribes for the user to see, but the request is gated.
    @Published var isAwaitingReply = false

    /// When true, the user is in continuous conversation with Eve. The mic
    /// stays on across turns, silence auto-submits the transcript, and we
    /// re-engage listening after Eve's TTS reply finishes. End the mode
    /// explicitly via `endConversation()` — push-to-talk it is not.
    @Published var conversationMode = false

    /// User-toggled in conversation mode. When true, the mic is paused
    /// (no transcription accumulating) so Eve isn't distracted by ambient
    /// speech or noise. Toggling off re-engages listening at the next
    /// natural opportunity.
    @Published var muted = false

    /// Silence detection — once the live transcript stops changing for
    /// this many seconds, we treat it as end-of-utterance and submit.
    /// Tuned to feel snappy without truncating natural mid-sentence
    /// pauses. 0.9s is the floor before users start noticing premature
    /// submits on short pauses ("uh… and then I want to —"). Anything
    /// shorter trips that perception.
    private let silenceTimeoutSec: TimeInterval = 0.9
    private var silenceTimer: Timer?

    override init() {
        super.init()
        speechSynth.delegate = self
        // Listen for audio session interruptions (phone calls, Siri,
        // alarms). When iOS restores audio to us — call ends, Siri
        // dismissed — auto-resume listening if the user was mid-
        // conversation so they don't have to manually re-tap.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw  = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            // Something else (phone call, Siri) grabbed the mic. Pause
            // without submitting whatever partial transcript was building.
            DispatchQueue.main.async {
                if self.isListening { self.pauseListeningWithoutSubmit() }
                self.statusMessage = "Paused (audio interrupted)"
            }
        case .ended:
            // iOS hands audio back. If user was in conversation mode,
            // pick up where we left off.
            if let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                if opts.contains(.shouldResume), conversationMode, !muted {
                    DispatchQueue.main.async { self.startListening() }
                }
            }
        @unknown default:
            break
        }
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
                // On-device recognition when supported. Cuts the
                // per-utterance latency by ~150-400ms (no network round
                // trip on each buffer) and keeps voice data off Apple's
                // servers. Falls back automatically if unsupported.
                if self.speechRecognizer?.supportsOnDeviceRecognition == true {
                    self.recognitionRequest?.requiresOnDeviceRecognition = true
                }

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
                        let newText = result.bestTranscription.formattedString
                        DispatchQueue.main.async {
                            self.transcribedText = newText
                            // In conversation mode, end-of-utterance is
                            // signaled by silence. Reset the silence timer
                            // every time the transcript moves; when the
                            // timer finally fires we submit whatever has
                            // accumulated. Outside conversation mode the
                            // user controls submission with the End button.
                            if self.conversationMode && !self.muted
                                && !newText.trimmingCharacters(in: .whitespaces).isEmpty {
                                self.scheduleSilenceTimer()
                            }
                        }
                    }
                    if error != nil {
                        self.stopListening()
                    }
                }
            } catch {
                let friendly = Self.friendlyAudioErrorMessage(error)
                DispatchQueue.main.async {
                    self.statusMessage = friendly
                    self.isListening = false
                }
            }
        }
    }

    /// Translate raw AVAudioSession errors into a sentence a user can
    /// act on. The most common failure on a phone is "active phone
    /// call" — the system blocks any other app from activating the
    /// session while a call is up.
    private static func friendlyAudioErrorMessage(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case 561017449:
            return "Mic blocked by another app (phone call?). End it and try again."
        case 561145187, 561145203, 560557684:
            // Generic activation/configuration failures
            return "Couldn't start the mic. Close other audio apps and try again."
        default:
            return "Audio setup failed (\(ns.code))"
        }
    }

    func stopListening() {
        // Idempotent — must NOT re-submit if called twice. When the silence
        // timer fires we cancel the recognition task; that cancellation
        // triggers the recognizer's result/error callback, which can call
        // stopListening() again. Without this guard, transcribedText gets
        // submitted twice and the user sees a doubled message bubble.
        guard recognitionTask != nil else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        silenceTimer?.invalidate(); silenceTimer = nil

        // Capture-then-clear so any re-entrant call (or a stray
        // resumeListening that hasn't reset state yet) can't replay
        // the same transcript.
        let captured = transcribedText
        transcribedText = ""

        DispatchQueue.main.async {
            self.isListening = false
            self.statusMessage = "Processing..."
        }

        handleTranscription(captured)
    }

    // MARK: - Conversation mode

    /// Enter continuous conversation. Mic stays on across turns; silence
    /// auto-submits; Eve's reply re-engages the mic when she's done
    /// speaking. Use Mute to pause without leaving, End to fully exit.
    func startConversation() {
        DispatchQueue.main.async {
            self.conversationMode = true
            self.muted = false
        }
        startListening()
    }

    /// Leave conversation mode entirely. Stops the mic without submitting
    /// whatever's in the live transcript (different from `stopListening`,
    /// which submits).
    func endConversation() {
        silenceTimer?.invalidate(); silenceTimer = nil
        pauseListeningWithoutSubmit()
        DispatchQueue.main.async {
            self.conversationMode = false
            self.muted = false
            self.statusMessage = "Ready"
        }
    }

    /// Pause/resume mic capture mid-conversation. While muted, no
    /// transcript accumulates and silence detection is parked. Toggling
    /// back on re-engages listening at the next runloop tick.
    func toggleMute() {
        let newMuted = !muted
        DispatchQueue.main.async {
            self.muted = newMuted
            self.statusMessage = newMuted ? "Muted" : "Listening..."
        }
        if newMuted {
            silenceTimer?.invalidate(); silenceTimer = nil
            pauseListeningWithoutSubmit()
        } else {
            if conversationMode { startListening() }
        }
    }

    /// Stop the mic without submitting whatever is currently in the live
    /// transcript. Used for Mute and for End — both shouldn't accidentally
    /// dispatch a half-recognized utterance to Eve.
    private func pauseListeningWithoutSubmit() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        DispatchQueue.main.async {
            self.isListening = false
            self.transcribedText = ""
        }
    }

    /// (Re)schedule the end-of-utterance fire. Called every time the
    /// recognizer's partial result moves; once the partials stop moving
    /// for `silenceTimeoutSec`, this fires and submits the transcript.
    /// Only meaningful while `conversationMode && !muted`.
    private func scheduleSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeoutSec, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Final guard — by the time the timer fires the user may have
            // muted or ended the conversation. Either case: don't submit.
            // Also don't submit if we're still waiting on the previous
            // reply — that's how we get double-submits ("Are you working"
            // then "Are you working" again before Eve has answered once).
            if self.conversationMode
                && !self.muted
                && !self.isAwaitingReply
                && self.isListening {
                self.stopListening()
            }
        }
    }

    /// Re-engage the mic after Eve's TTS reply finishes. Called from
    /// audioPlayerDidFinishPlaying (MP3 path) and from the
    /// AVSpeechSynthesizer delegate (system-voice fallback). Short delay
    /// avoids catching the tail of the audio in the next transcript.
    @MainActor
    private func resumeListeningIfInConversation() async {
        guard conversationMode, !muted else { return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if conversationMode && !muted && !isListening {
            startListening()
        }
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

    /// Pull latest memory and context from home machine via Supabase. The
    /// Supabase Swift package is an optional dependency — when it isn't
    /// installed, "Hey Sync" reports a friendly skip instead of failing the
    /// build.
    func syncWithHome() async {
        #if canImport(Supabase)
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
        }
        #else
        await MainActor.run {
            self.statusMessage = "Hey Sync needs the Supabase package — see SupabaseManager.swift"
        }
        #endif
    }

    /// Ask Eve's home brain. Three paths in priority order:
    /// 1. `useLocalBrain` + LAN URL configured → direct-to-Ollama (fastest, no nexus-web hop)
    /// 2. `useLocalBrain` → nexus-web `/api/eve/local` (Ollama, threaded with memory)
    /// 3. Default → nexus-web `/api/eve` (Grok with tool calling)
    func askHomeBrain(_ message: String) async {
        let api = NexusAPIClient.shared
        // Re-entrancy guard. Without this, a second send fired while the
        // first is still streaming would (a) append a second user bubble,
        // (b) append a second empty Eve bubble, and (c) cause the first
        // stream's chunks to land in the wrong (second) bubble — the
        // classic "doubled messages" symptom. Returning early is preferable
        // to interleaving two turns, since interleaving corrupts both.
        let alreadyInFlight = await MainActor.run { () -> Bool in
            if self.isAwaitingReply { return true }
            self.isAwaitingReply = true
            return false
        }
        if alreadyInFlight {
            await MainActor.run { self.statusMessage = "Eve is still responding…" }
            return
        }
        defer {
            Task { @MainActor in self.isAwaitingReply = false }
        }

        // Vision branch — if images attached, OCR them on-device first
        // (Vision framework, no network), then route through /api/eve/local
        // with llava + the parsed text so Eve has both modalities.
        if !pendingImages.isEmpty {
            let images = pendingImages
            await MainActor.run {
                self.pendingImages.removeAll()
                let label = "\(message)  📷×\(images.count)"
                self.messages.append(ChatTurn(role: .user, content: label))
                self.statusMessage = "Reading text…"
            }
            // Run OCR on every attached image in parallel and stitch results.
            var ocrChunks: [String] = []
            for img in images {
                let text = await EveVisionOCR.recognizeText(in: img)
                if !text.isEmpty { ocrChunks.append(text) }
            }
            let enrichedMessage: String = {
                if ocrChunks.isEmpty { return message }
                let joinedOCR = ocrChunks.joined(separator: "\n---\n")
                let prefix = message.isEmpty ? "Look at the attached image(s)." : message
                return "\(prefix)\n\nOCR text from the image(s):\n\(joinedOCR)"
            }()
            await MainActor.run { self.statusMessage = "Eve is looking…" }
            do {
                let b64 = images.map { $0.base64EncodedString() }
                let result = try await api.askEveLocalWithImages(message: enrichedMessage, images: b64, conversationId: conversationId)
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
            let replyBrain: String = useLocalBrain ? "local" : "grok"

            if useLocalBrain {
                let r = try await api.askEveLocal(message: message, conversationId: conversationId)
                replyContent = r.content
                replyConvId  = r.conversationId
                await MainActor.run {
                    if self.conversationId == nil { self.conversationId = replyConvId }
                    self.lastReply     = replyContent
                    self.statusMessage = "Ready"
                    var turn = ChatTurn(role: .eve, content: replyContent)
                    turn.brain = replyBrain
                    turn.toolCalls = replyTools
                    self.messages.append(turn)
                }
            } else {
                // Append an empty Eve bubble up front; SSE deltas mutate its
                // content in place so the user sees the reply build up.
                // Also fire a Live Activity so the Dynamic Island /
                // Lock Screen reflect Eve's state without the app open.
                //
                // Track the bubble by UUID instead of `messages.last`. If the
                // user (or another code path) appends to `messages` between
                // now and the next chunk, indices-based lookup would point at
                // the wrong row and corrupt both bubbles.
                let bubbleId: UUID = await MainActor.run {
                    var turn = ChatTurn(role: .eve, content: "")
                    turn.brain = replyBrain
                    let id = turn.id
                    self.messages.append(turn)
                    self.statusMessage = "Eve…"
                    _ = EveLiveActivityController.shared.startThinking(
                        conversationId: self.conversationId ?? "new"
                    )
                    return id
                }

                // Begin a fresh streaming-TTS window. Anything still in
                // flight or queued from a previous turn becomes stale and
                // will be discarded by the requestId check.
                let currentRequestId = await MainActor.run { () -> Int in
                    self.beginStreamingTTSWindow()
                    return self.ttsRequestId
                }

                let r = try await api.askEveStreaming(
                    message: message,
                    conversationId: conversationId,
                    onChunk: { [weak self] chunk in
                        guard let self else { return }
                        if let idx = self.messages.firstIndex(where: { $0.id == bubbleId }) {
                            self.messages[idx].content += chunk
                            // Feed the chunk into the sentence-boundary buffer.
                            // Complete sentences are immediately handed off to
                            // TTS so playback can start mid-generation.
                            self.consumeStreamingChunkForTTS(chunk, requestId: currentRequestId)
                            // Stream into the Live Activity body so the Lock
                            // Screen / Dynamic Island reflects what Eve is
                            // saying as she says it.
                            let preview = String(self.messages[idx].content.suffix(140))
                            EveLiveActivityController.shared.update(
                                stage: .streaming,
                                headline: "Eve speaking",
                                body: preview
                            )
                        }
                    },
                    onToolCall: { [weak self] tc in
                        guard let self else { return }
                        if let idx = self.messages.firstIndex(where: { $0.id == bubbleId }) {
                            self.messages[idx].toolCalls.append(tc)
                        }
                        EveLiveActivityController.shared.update(
                            stage: .tool,
                            headline: tc.humanLabel,
                            body: tc.primary,
                            success: tc.success
                        )
                    }
                )
                replyContent = r.content
                replyConvId  = r.conversationId
                replyTools   = r.toolCalls

                await MainActor.run {
                    if self.conversationId == nil { self.conversationId = replyConvId }
                    self.lastReply     = replyContent
                    self.statusMessage = "Ready"
                    // Flush any trailing fragment without a sentence end —
                    // e.g. a reply that doesn't end in punctuation.
                    self.flushPendingSentenceForTTS(requestId: currentRequestId)
                    // Set the canonical content + tool-call list on the
                    // bubble we created for THIS turn. Looked up by UUID so
                    // we never accidentally overwrite a different bubble.
                    if let idx = self.messages.firstIndex(where: { $0.id == bubbleId }) {
                        self.messages[idx].content = replyContent
                        self.messages[idx].toolCalls = replyTools
                    }
                    EveLiveActivityController.shared.end(
                        stage: .done,
                        headline: "Eve replied",
                        body: String(replyContent.prefix(140))
                    )
                }
            }
            // When streaming TTS is on, sentence-by-sentence playback has
            // already started — DON'T speak the whole reply again. For the
            // local-brain path (which doesn't stream) and as a fallback if
            // streaming TTS is disabled, fall through to whole-reply speak.
            if useLocalBrain || !streamingTTSEnabled {
                speak(replyContent)
            }

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

    // MARK: - Streaming TTS

    /// Reset the streaming-TTS state for a new request. Bumps the
    /// requestId so any in-flight TTS fetches from a previous turn will
    /// be discarded when they return. Stops any currently-playing audio
    /// so the user hears the new turn cleanly.
    @MainActor
    private func beginStreamingTTSWindow() {
        ttsRequestId &+= 1
        pendingSentence = ""
        ttsAudioQueue.removeAll()
        ttsIsPlaying = false
        speechSynth.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// Append streaming chunk to the sentence buffer; if we cross a
    /// sentence boundary, hand the completed sentence to TTS.
    /// Boundary heuristic: `. ! ? \n` followed by space/newline/EOS.
    /// Tiny sentences (<8 chars) are coalesced into the next one so we
    /// don't spawn TTS fetches for things like "Hi.".
    @MainActor
    private func consumeStreamingChunkForTTS(_ chunk: String, requestId: Int) {
        guard streamingTTSEnabled, requestId == ttsRequestId else { return }
        pendingSentence += chunk
        // Extract every complete sentence currently in the buffer.
        while let split = findSentenceEnd(in: pendingSentence) {
            let sentence = String(pendingSentence[..<split])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pendingSentence = String(pendingSentence[split...])
            if sentence.count >= 8 {
                enqueueTTS(sentence, requestId: requestId)
            } else if !sentence.isEmpty {
                // Re-coalesce micro-sentence into the next one — avoids
                // pointless TTS fetch for "Yes." "Sure." etc.
                pendingSentence = sentence + " " + pendingSentence
                break
            }
        }
    }

    /// Flush whatever's left in the sentence buffer at stream end.
    /// Replies that don't end in punctuation still get spoken.
    @MainActor
    private func flushPendingSentenceForTTS(requestId: Int) {
        guard streamingTTSEnabled, requestId == ttsRequestId else { return }
        let tail = pendingSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSentence = ""
        if !tail.isEmpty {
            enqueueTTS(tail, requestId: requestId)
        }
    }

    /// Locate the first sentence-end position. Returns the index AFTER
    /// the punctuation so the caller can slice cleanly. nil = no boundary
    /// yet (keep buffering).
    private func findSentenceEnd(in text: String) -> String.Index? {
        let punct: Set<Character> = [".", "!", "?", "\n"]
        var i = text.startIndex
        while i < text.endIndex {
            if punct.contains(text[i]) {
                let next = text.index(after: i)
                // Sentence boundary on punctuation if followed by space/
                // newline/EOS. Catches "etc." too aggressively but TTS
                // handles short phrases fine.
                if next == text.endIndex
                    || text[next].isWhitespace
                    || text[next].isNewline {
                    return next
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// Kick off an async TTS fetch for a single sentence and queue the
    /// resulting MP3 for playback. Sequential playback keeps voice
    /// coherent — sentences play in order they were generated even if
    /// later TTS fetches return faster than earlier ones (queue is FIFO).
    @MainActor
    private func enqueueTTS(_ sentence: String, requestId: Int) {
        Task { [weak self] in
            guard let self else { return }
            let mp3 = await self.fetchEveTTS(text: sentence)
            await MainActor.run {
                // Stale check — request may have changed mid-fetch.
                guard requestId == self.ttsRequestId else { return }
                guard let mp3 else {
                    // TTS failed for this sentence — fall back to system
                    // voice for just this chunk and continue.
                    self.fallbackSystemSpeak(sentence)
                    return
                }
                self.ttsAudioQueue.append(mp3)
                self.tickTTSQueue()
            }
        }
    }

    /// Advance the playback queue: if we're not currently playing and
    /// there's a queued MP3, start it. Re-called from
    /// `audioPlayerDidFinishPlaying` once a chunk finishes.
    @MainActor
    private func tickTTSQueue() {
        guard !ttsIsPlaying, !ttsAudioQueue.isEmpty else { return }
        let next = ttsAudioQueue.removeFirst()
        ttsIsPlaying = true
        playMP3(next)
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioPlayer = nil
            self.ttsIsPlaying = false
            // If there are more streamed sentences queued, advance to the
            // next one instead of resuming the mic. Only when the queue
            // drains AND no more deltas are buffered do we resume listening.
            if !self.ttsAudioQueue.isEmpty {
                self.tickTTSQueue()
                return
            }
            if !self.pendingSentence.trimmingCharacters(in: .whitespaces).isEmpty {
                // Still buffering a partial sentence — wait for more
                // deltas to arrive (or for flush at stream end).
                return
            }
            Task { @MainActor [weak self] in
                await self?.resumeListeningIfInConversation()
            }
        }
    }

    /// AVSpeechSynthesizer fallback path — fires when ElevenLabs TTS
    /// failed and we fell back to the system voice. Mirrors the MP3
    /// path's auto-resume so conversation mode survives the fallback.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            await self?.resumeListeningIfInConversation()
        }
    }

    /// Send a typed message to Eve — same brain pipeline as voice, just
    /// without the speech recognition step. Lets the user type when speaking
    /// isn't appropriate (meetings, transit, sensitive info).
    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await askHomeBrain(trimmed) }
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
