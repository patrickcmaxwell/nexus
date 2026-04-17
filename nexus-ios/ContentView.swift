// ContentView.swift
// Nexus iOS — main voice interface

import SwiftUI

struct ContentView: View {
    @StateObject private var voice = EveVoiceManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Eve status
                VStack(spacing: 12) {
                    Text("EVE")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.indigo)
                        .tracking(6)

                    // Pulse ring when listening
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

                // Transcription
                if !voice.transcribedText.isEmpty {
                    Text(voice.transcribedText)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }

                // Status
                Text(voice.statusMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)

                Spacer()

                // Talk button
                Button(action: {
                    if voice.isListening {
                        voice.stopListening()
                    } else {
                        voice.startListening()
                    }
                }) {
                    Text(voice.isListening ? "Done" : "Talk to Eve")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(voice.isListening ? Color.red.opacity(0.8) : Color.indigo)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .animation(.easeInOut, value: voice.isListening)
    }
}

#Preview {
    ContentView()
}
