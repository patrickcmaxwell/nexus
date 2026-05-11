// EveAppIntents.swift
// AppIntents that expose Eve to Siri, the Action Button, the Shortcuts app,
// and any system-level "automate this" surface. No extension target is
// needed — these intents run in the app process via AppIntentsExtensionLite.
//
// Contract: each intent is a small, focused verb. They go through the same
// NexusAPIClient that the in-app voice flow uses, so auth + brain selection
// are consistent. The user never has to copy a session token between Siri
// and the app — once they're signed in once, every intent works.
//
// Action Button binding: in iOS Settings → Action Button → Shortcut, the
// user can pick any of these. "Hey Siri, ask Eve <X>" likewise routes to
// AskEveIntent with X as the parameter.

import AppIntents
import Foundation

// MARK: - Ask Eve

/// "Hey Siri, ask Eve <something>"
/// "Hey Siri, ask Nexus what's next"
struct AskEveIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Eve"
    static let description = IntentDescription("Send a message to Eve and get her reply spoken or shown.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Message", description: "What to ask Eve")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let _ = NexusAPIClient.shared.sessionId else {
            return .result(dialog: "You need to sign in to Nexus on your phone first.")
        }
        do {
            let result = try await NexusAPIClient.shared.askEve(message: message)
            return .result(dialog: IntentDialog(stringLiteral: result.content))
        } catch NexusAPIClient.APIError.unauthorized {
            return .result(dialog: "Your Nexus session expired — open the app to sign in.")
        } catch {
            return .result(dialog: "Eve didn't answer: \(error.localizedDescription)")
        }
    }
}

// MARK: - Briefing

/// "Hey Siri, brief me from Eve"
struct EveBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "Brief me from Eve"
    static let description = IntentDescription("Get a short summary of what changed in Nexus since yesterday.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard NexusAPIClient.shared.sessionId != nil else {
            return .result(dialog: "Sign in to Nexus on your phone first.")
        }
        do {
            let b = try await NexusAPIClient.shared.fetchBriefing()
            // Compose a calm, speakable two-sentence brief.
            var parts: [String] = []
            parts.append("\(b.stats.activeOps) operations, \(b.stats.activeAgents) agents active.")
            if b.delta.findings.totalCount > 0 {
                parts.append("\(b.delta.findings.totalCount) new findings.")
            }
            if !b.delta.newOperations.isEmpty {
                parts.append("\(b.delta.newOperations.count) new operations.")
            }
            if !b.delta.completedResearch.isEmpty {
                parts.append("\(b.delta.completedResearch.count) research items completed.")
            }
            if parts.count == 1 { parts.append("All quiet otherwise.") }
            return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
        } catch {
            return .result(dialog: "Briefing unavailable: \(error.localizedDescription)")
        }
    }
}

// MARK: - New conversation

/// "Hey Siri, new Eve conversation"
struct NewEveConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "New Eve conversation"
    static let description = IntentDescription("Start a fresh Eve conversation thread.")
    static let openAppWhenRun: Bool = true  // open the app so the user lands on the empty thread

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app coordinator listens for this and resets the active
        // conversation on next launch via UserDefaults.
        UserDefaults.standard.set(true, forKey: "nexus.intent.newConversation")
        return .result()
    }
}

// MARK: - Operation status

/// "Hey Siri, Eve operation status"
struct EveOperationsStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Eve operations status"
    static let description = IntentDescription("Speak the active operations and their statuses.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard NexusAPIClient.shared.sessionId != nil else {
            return .result(dialog: "Sign in to Nexus on your phone first.")
        }
        do {
            let ops = try await NexusAPIClient.shared.fetchOperations()
            if ops.isEmpty {
                return .result(dialog: "No operations.")
            }
            let active = ops.filter { $0.status.lowercased() == "active" }
            let phrase: String
            if active.isEmpty {
                phrase = "\(ops.count) operations total, none active."
            } else if active.count == 1 {
                phrase = "One active operation: \(active[0].name)."
            } else {
                phrase = "\(active.count) active operations: " +
                    active.prefix(5).map(\.name).joined(separator: ", ") + "."
            }
            return .result(dialog: IntentDialog(stringLiteral: phrase))
        } catch {
            return .result(dialog: "Couldn't reach Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Shortcut catalog

/// Tells Shortcuts.app what intents this app exposes, gives them friendly
/// invocation phrases, and groups them under "Eve". Without this, the user
/// has to manually search for each intent in the gallery.
struct NexusShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .lime }

    static var appShortcuts: [AppShortcut] {
        // Phrases must contain `\(.applicationName)` and parameter slots in
        // App Shortcut phrases must be AppEntity/AppEnum types — plain
        // String parameters can't be slotted, so AskEve uses parameter-less
        // phrases (Siri then prompts the user for the message).
        AppShortcut(
            intent: AskEveIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
            ],
            shortTitle: "Ask Eve",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: EveBriefingIntent(),
            phrases: [
                "Brief me from \(.applicationName)",
                "\(.applicationName) briefing",
            ],
            shortTitle: "Brief me",
            systemImageName: "newspaper"
        )
        AppShortcut(
            intent: NewEveConversationIntent(),
            phrases: [
                "New \(.applicationName) conversation",
                "Start a fresh \(.applicationName) chat",
            ],
            shortTitle: "New conversation",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: EveOperationsStatusIntent(),
            phrases: [
                "\(.applicationName) operations",
                "What's running in \(.applicationName)",
            ],
            shortTitle: "Operations status",
            systemImageName: "list.bullet.rectangle"
        )
    }
}
