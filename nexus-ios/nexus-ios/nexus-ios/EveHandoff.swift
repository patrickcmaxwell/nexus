// EveHandoff.swift
// NSUserActivity glue so the active Eve conversation can be picked up on
// another logged-in device — Mac (Lumen Desktop), iPad, or another iPhone.
//
// Why: matches Apple's Handoff UX. When you have a conversation open on
// the phone and walk to your Mac, the Lumen app icon appears at the
// far-right of the Mac dock with a phone glyph. One click resumes the
// thread there. Pure NSUserActivity, no extra plumbing — Apple's continuity
// service handles discovery + transport.
//
// Activity also flows into Siri suggestions, Spotlight (already-running
// suggestions), and Lock-Screen "Recent" — all for free.

import Foundation
import CoreSpotlight

enum EveHandoff {
    /// Same value used by EveSpotlight so a Spotlight tap and a Handoff tap
    /// both flow through the same continuation handler.
    static let activityType = EveSpotlight.activityType

    /// Build a published NSUserActivity for a conversation. Hand the result
    /// to a SwiftUI view via `.userActivity(activityType, isActive:) { ... }`
    /// so it auto-publishes while visible and clears when not.
    static func makeActivity(conversationId: String, title: String, source: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = title.isEmpty ? "Eve conversation" : title
        activity.userInfo = [
            "conversationId": conversationId,
            "source":         source,
        ]
        activity.requiredUserInfoKeys = ["conversationId"]
        // Make Apple Continuity broadcast it across the user's devices.
        activity.isEligibleForHandoff   = true
        // Surface in Spotlight's "recent" rail without needing a full re-index.
        activity.isEligibleForSearch    = true
        // Let Siri suggest it ("you usually open this conversation around 9am").
        activity.isEligibleForPrediction = true

        // CoreSpotlight overlay: lets the system stitch this activity to the
        // already-indexed CSSearchableItem so a Spotlight tap routes to the
        // right continuation handler.
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = activity.title
        attrs.contentDescription = "Resume this Eve conversation"
        activity.contentAttributeSet = attrs
        activity.persistentIdentifier = conversationId

        return activity
    }
}
