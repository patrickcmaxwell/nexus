// EveOrbWindow.swift
//
// Popout window dedicated to the Eve orb. Director can pull this onto a
// second monitor or pin it as a floating panel while doing other work and
// still see Eve's state at a glance.
//
// Window state mirrors the main store — same eveStatus, same audioLevel —
// so the orb here animates in lockstep with the orb in the rail.

import SwiftUI
import AppKit

struct EveOrbWindow: View {
    @EnvironmentObject var store: LumenStore
    @AppStorage("lumen.orbWindow.alwaysOnTop") private var alwaysOnTop: Bool = false
    @AppStorage("lumen.orbWindow.compact") private var compact: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            header
            EveOrb(status: store.eveStatus, audioLevel: store.audioLevel)
                .scaleEffect(compact ? 0.75 : 1.0)
                .frame(height: compact ? 200 : 260)
            statusReadout
            footer
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color(.windowBackgroundColor)
                LinearGradient(
                    colors: [C.eve.opacity(0.05), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
        )
        .background(WindowAccessor(alwaysOnTop: alwaysOnTop))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.eveStatus.color)
                .frame(width: 6, height: 6)
                .shadow(color: store.eveStatus.color, radius: 4)
            Text("EVE · STATUS WINDOW")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.5)
                .foregroundColor(C.eve)
            Spacer()
            Button(action: { compact.toggle() }) {
                Image(systemName: compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(compact ? "Larger" : "Compact")
            Button(action: { alwaysOnTop.toggle() }) {
                Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(alwaysOnTop ? C.eve : .secondary)
            }
            .buttonStyle(.plain)
            .help(alwaysOnTop ? "Unpin (no longer always-on-top)" : "Pin always-on-top")
        }
    }

    private var statusReadout: some View {
        HStack(spacing: 8) {
            Text(store.eveStatus.label.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2.5)
                .foregroundColor(store.eveStatus.color)
            if store.eveStatus == .speaking || store.eveStatus == .listening || store.eveStatus == .thinking {
                HStack(spacing: 1.5) {
                    ForEach(0..<10, id: \.self) { i in
                        let bar = max(0.15, min(1.0, CGFloat(store.audioLevel) * CGFloat(i + 1) / 9.0))
                        Capsule()
                            .fill(store.eveStatus.color.opacity(0.7))
                            .frame(width: 2.5, height: 5 + bar * 18)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(stateExplanation)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var stateExplanation: String {
        switch store.eveStatus {
        case .idle:      return "Standing by. Speak or type to engage."
        case .listening: return "Listening. Rings track your microphone level."
        case .thinking:  return "Processing — reasoning + tool calls in flight."
        case .speaking:  return "Replying. Rings track Eve's voice amplitude."
        }
    }
}

/// Bridges SwiftUI to the underlying NSWindow so we can flip the
/// `.floating` level for "always on top." Cleanest way to do this in
/// SwiftUI for macOS without dropping to AppKit windowing.
private struct WindowAccessor: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.level = alwaysOnTop ? .floating : .normal
            // Borderless-ish styling — keep a title bar for drag-to-move
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        }
    }
}
