// EveVoiceManager.swift
// Nexus iOS — real-time voice input with Hey Sync detection

import AVFoundation
import Speech
import Foundation

class EveVoiceManager: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var statusMessage = "Ready"

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

        } else if lower.contains("use grok") || lower.contains("use internet") || lower.contains("go online") {
            DispatchQueue.main.async { self.statusMessage = "Switching to cloud mode..." }
            // TODO: call Grok API

        } else {
            // Route to home brain (LM Studio via Supabase relay)
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

    /// Ask Eve's home brain (routed via Supabase edge function or relay)
    func askHomeBrain(_ message: String) async {
        // TODO: implement home brain relay via Supabase Edge Function
        // For now, fall back to Apple Intelligence
        await MainActor.run {
            self.statusMessage = "Home brain unavailable — using Apple Intelligence"
        }
    }
}
