// EveSpotlight.swift
// Index conversations into CoreSpotlight so iOS system search hits Eve
// content. Tapping a result opens the app via NSUserActivity carrying the
// conversation id; ContentView's continuation handler resumes the thread.
//
// Privacy: indexing is local-only by default (CSSearchableItemAttributeSet
// without `setPublic` keeps it on-device). No payload syncs to Apple.

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

enum EveSpotlight {
    static let domainIdentifier = "io.talkcircles.nexus.conversations"
    static let activityType     = "io.talkcircles.nexus.conversation"

    /// Re-index all conversations. Cheap to call after a successful
    /// fetchConversations() — Spotlight handles dedup via the unique id.
    static func reindex(_ conversations: [NexusAPIClient.ConversationSummary]) {
        let items = conversations.map { c -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = c.title.isEmpty ? "Untitled conversation" : c.title
            attrs.contentDescription = "Eve conversation · \(c.source) · \(c.updated_at)"
            attrs.contentCreationDate = ISO8601DateFormatter().date(from: c.updated_at)
            attrs.keywords = ["Eve", "Nexus", c.source]
            return CSSearchableItem(
                uniqueIdentifier: c.id,
                domainIdentifier: domainIdentifier,
                attributeSet: attrs
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error { NSLog("[nexus-spotlight] index error: %@", error.localizedDescription) }
        }
    }

    /// Drop the entire Eve index. Called on sign-out so the previous user's
    /// conversation titles aren't searchable from the system.
    static func wipe() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in }
    }
}
