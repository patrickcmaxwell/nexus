// EveLiveActivityController.swift
// Main-app side controller that starts/updates/ends Live Activities. Lives
// inside the main app target. Calls into ActivityKit only on iOS 16.1+
// (the Live Activity API surface is gated by availability).
//
// Mirrors the EveActivityAttributes shape declared in the Widget Extension.
// Keep these two declarations byte-identical — ActivityKit serializes
// across the process boundary and a mismatch silently fails the activity.
//
// Usage (from EveVoiceManager.askHomeBrain):
//   let h = EveLiveActivityController.shared.startThinking(conversationId: convId)
//   ... // streaming, updates h.update(stage: .streaming, body: partial)
//   h.end(stage: .done, body: final)

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Mirror of the widget-side struct. Keep in sync.
struct EveActivityAttributes: Codable, Hashable {
    public struct ContentState: Codable, Hashable {
        var stage: Stage
        var headline: String
        var body: String
        var success: Bool
        public enum Stage: String, Codable, Hashable { case thinking, streaming, tool, done }
    }
    var conversationId: String
}

#if canImport(ActivityKit)
extension EveActivityAttributes: ActivityAttributes { }
#endif

/// Singleton that owns the currently-running activity (if any). At most
/// one Eve activity runs at a time — interleaving multiple "Eve thinking"
/// indicators would be confusing.
@MainActor
final class EveLiveActivityController {
    static let shared = EveLiveActivityController()
    private init() {}

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var current: Activity<EveActivityAttributes>?
    #endif

    /// Start an "Eve thinking…" activity. Returns a token the caller uses
    /// to update + end. No-op (returns nil) on iOS 16.0 or earlier, or if
    /// Live Activities are disabled by the user.
    func startThinking(conversationId: String) -> Token {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return Token() }
            let attrs = EveActivityAttributes(conversationId: conversationId)
            let initial = EveActivityAttributes.ContentState(
                stage: .thinking,
                headline: "Eve thinking…",
                body: "",
                success: true
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content: ActivityContent(state: initial, staleDate: Date().addingTimeInterval(120)),
                    pushType: nil
                )
                current = activity
                return Token(id: activity.id)
            } catch {
                NSLog("[nexus-activity] start failed: %@", error.localizedDescription)
            }
        }
        #endif
        return Token()
    }

    /// Update the active activity's state. Cheap to call frequently — the
    /// system coalesces and rate-limits.
    func update(stage: EveActivityAttributes.ContentState.Stage, headline: String, body: String, success: Bool = true) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard let activity = current else { return }
            let state = EveActivityAttributes.ContentState(
                stage: stage, headline: headline, body: body, success: success
            )
            Task {
                await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)))
            }
        }
        #endif
    }

    /// End the activity. Optionally show a final state (e.g. "done") for
    /// `lingerSeconds` before it disappears from the Lock Screen.
    func end(stage: EveActivityAttributes.ContentState.Stage, headline: String, body: String, success: Bool = true, linger: TimeInterval = 4) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard let activity = current else { return }
            let state = EveActivityAttributes.ContentState(
                stage: stage, headline: headline, body: body, success: success
            )
            Task {
                await activity.end(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(linger)),
                    dismissalPolicy: .after(Date().addingTimeInterval(linger))
                )
                self.current = nil
            }
        }
        #endif
    }

    struct Token { var id: String? = nil }
}
