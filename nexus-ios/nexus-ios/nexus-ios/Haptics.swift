// Haptics.swift
//
// Tiny wrapper around UIFeedbackGenerator so every interaction in the
// app gets the right haptic without each call site repeating the boiler.
//
// Why centralize: the call site stays one short line, generators are
// `prepare()`-warmed for low-latency feedback, and if we ever want to
// gate haptics on a setting (some users dislike them) the toggle lives
// in one place.
import UIKit

enum Haptics {
    /// Snappy tap — best for tab switches, segment changes, picker rows.
    /// Lighter than `tap` so frequent UI navigation doesn't feel buzzy.
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare(); g.impactOccurred()
    }

    /// Standard button press feel. Use for primary actions: send, run,
    /// submit, toggle.
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare(); g.impactOccurred()
    }

    /// Heavier — reserve for state changes the user really wants to feel
    /// (mode entry/exit, irreversible toggle).
    static func heavy() {
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.prepare(); g.impactOccurred()
    }

    /// Success / error / warning notifications. Avoid for routine UI;
    /// users overload on these fast.
    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error()   { notify(.error) }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(type)
    }

    /// Selection ticks — picker rolling, slider crossing detent. Lower
    /// energy than `light()`, designed for repeated firing.
    static func select() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }
}
