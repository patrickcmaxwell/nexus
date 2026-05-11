// ContentView.swift
// Watch UI — tap-to-talk to Eve via the paired iPhone.
//
// Flow: tap "Talk" → watchOS native dictation/scribble sheet collects the
// transcript → we send it to the iPhone via WCSession → the iPhone forwards
// to /api/eve through NexusAPIClient → reply text comes back. AVSpeech-
// Synthesizer reads it aloud + a haptic confirms.
//
// Why TextFieldLink (not SFSpeechRecognizer): watchOS does not ship the
// Speech framework on the watch. Apple wants us to use the system dictation
// sheet, which TextFieldLink wraps. It also gives the user the option to
// scribble or use Smart Reply suggestions if voice isn't appropriate.

import SwiftUI
import Combine
import WatchKit
import AVFoundation

struct ContentView: View {
    @StateObject private var voice  = WatchVoice()
    @StateObject private var bridge = WatchPhoneBridge.shared

    var body: some View {
        VStack(spacing: 8) {
            statusLine
                .font(.caption2)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !voice.transcript.isEmpty {
                        Text(voice.transcript)
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                    if !voice.lastReply.isEmpty {
                        Text(voice.lastReply)
                            .font(.body)
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Watch-native dictation: TextFieldLink presents the system
            // mic/scribble sheet. The closure receives the final text.
            TextFieldLink(
                prompt: Text("Ask Eve"),
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Talk")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                },
                onSubmit: { transcript in
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await voice.send(trimmed) }
                }
            )
            .tint(.accentColor)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var statusLine: some View {
        if !bridge.phoneReachable {
            Label("Phone unreachable", systemImage: "iphone.slash")
                .foregroundStyle(.orange)
        } else if voice.isThinking {
            Label("Eve is thinking…", systemImage: "brain")
        } else if let err = voice.errorMessage {
            Label(err, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            Label("Ready", systemImage: "iphone.radiowaves.left.and.right")
        }
    }
}

@MainActor
final class WatchVoice: ObservableObject {
    @Published var isThinking  = false
    @Published var transcript  = ""
    @Published var lastReply   = ""
    @Published var errorMessage: String? = nil

    private let speechSynth = AVSpeechSynthesizer()

    func send(_ text: String) async {
        transcript = text
        errorMessage = nil
        isThinking = true
        defer { isThinking = false }
        WKInterfaceDevice.current().play(.click)

        do {
            let reply = try await WatchPhoneBridge.shared.askPhone(text)
            lastReply = reply
            speak(reply)
            WKInterfaceDevice.current().play(.success)
        } catch WatchPhoneBridge.BridgeError.unreachable {
            errorMessage = "Phone unreachable — queued."
            WKInterfaceDevice.current().play(.failure)
        } catch WatchPhoneBridge.BridgeError.replyError(let msg) {
            errorMessage = msg
            WKInterfaceDevice.current().play(.failure)
        } catch {
            errorMessage = "Send failed"
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func speak(_ text: String) {
        let speakable = String(text.prefix(400))
        let utterance = AVSpeechUtterance(string: speakable)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate  = 0.5
        speechSynth.speak(utterance)
    }
}

#Preview {
    ContentView()
}
