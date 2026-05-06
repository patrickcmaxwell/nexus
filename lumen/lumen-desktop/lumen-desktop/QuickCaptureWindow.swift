// QuickCaptureWindow.swift
//
// Floating mini-window for "drop a thought" interactions with Eve. Triggered
// by ⌘⌥N when Lumen is the active app, or via menu / menu-bar item. Sends
// straight to /api/eve (Grok + tools) so Eve can actually act on it
// (e.g., "make a memory: …", "create an op called X").
//
// Each invocation is a fresh thread sourced as "quickcapture" so it doesn't
// pollute the main chat history but is still findable in the conversations
// list (filterable later if it becomes noisy).

import SwiftUI

struct QuickCaptureWindow: View {
    @EnvironmentObject var store: LumenStore
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var input: String = ""
    @State private var sending = false
    @State private var reply: String = ""
    @State private var brainTag: String = ""
    @State private var error: String? = nil
    @State private var dismissTimer: Timer?
    @FocusState private var inputFocused: Bool

    private let dismissAfterReplySec: TimeInterval = 8.0

    var body: some View {
        ZStack {
            // Subtle particle field — same as main chat, lower intensity.
            CosmicParticles(intensity: sending ? 0.85 : (reply.isEmpty ? 0.32 : 0.55), tint: C.eve)
                .opacity(0.85)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: sending)

            VStack(alignment: .leading, spacing: 0) {
                header
                inputBar
                if !reply.isEmpty {
                    replyView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let err = error {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(C.danger)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: 540)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(C.eve.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 28, y: 8)
        .padding(20)
        .onAppear {
            inputFocused = true
        }
        // ESC to dismiss
        .background(
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        )
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sending ? C.eve : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .shadow(color: sending ? C.eve : .clear, radius: 5)
            Text("EVE · QUICK CAPTURE")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.5)
                .foregroundColor(C.eve)
            if !brainTag.isEmpty {
                Text(brainTag.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(C.eve)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(C.eve.opacity(0.13))
                    .overlay(Capsule().strokeBorder(C.eve.opacity(0.35), lineWidth: 0.5))
                    .clipShape(Capsule())
            }
            Spacer()
            Text("ESC to dismiss")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $input,
                prompt: Text("Tell Eve what's on your mind…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .textFieldStyle(.plain)
            .focused($inputFocused)
            .onSubmit { submit() }
            .disabled(sending)

            Button(action: submit) {
                Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(canSubmit ? C.eve : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(C.surfaceHi.opacity(0.4))
    }

    private var replyView: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(C.eve).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("EVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(C.eve)
                Text(MentionRenderer.attributed(reply))
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        if MentionRenderer.handle(url: url) { return .handled }
                        return .systemAction
                    })
            }
            Spacer(minLength: 0)
            Button(action: openMain) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9, weight: .bold))
                    Text("OPEN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Continue this thread in the main Lumen window")
        }
        .padding(16)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        error = nil
        dismissTimer?.invalidate()
        dismissTimer = nil

        Task { @MainActor in
            do {
                // Fresh thread per quick capture — pass nil conversationId.
                let result = try await LumenAPIManager.shared.callNexusEve(
                    message: text,
                    conversationId: nil,
                    history: ArraySlice<ChatMessage>([])
                )
                reply = result.content
                _ = result.toolCalls  // QuickCapture doesn't render tool cards yet
                brainTag = "grok"
                input = ""
                sending = false
                scheduleAutoDismiss()
            } catch {
                self.error = "Eve unreachable. Try the main window."
                sending = false
            }
        }
    }

    private func scheduleAutoDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissAfterReplySec, repeats: false) { _ in
            DispatchQueue.main.async { dismiss() }
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismissWindow(id: "quick-capture")
    }

    private func openMain() {
        // Hand off the thought to the main window — open or focus it.
        dismiss()
        openWindow(id: "main")
    }
}
