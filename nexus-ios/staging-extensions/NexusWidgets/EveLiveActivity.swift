// EveLiveActivity.swift
// Dynamic Island + Lock Screen Live Activity that surfaces:
//   1. A streaming Eve reply (compact: "Eve…", expanded: the partial text)
//   2. An Arena tool call in progress ("Creating task…", "Routing payment…")
//
// The main app starts the activity via `Activity<EveActivityAttributes>.request(...)`
// when it kicks off `askEveStreaming` (or any Arena call), updates it on
// each SSE delta, and ends it on completion.
//
// Add this file to the Widget Extension target. Live Activities require:
//   - Info.plist key `NSSupportsLiveActivities = YES` on the MAIN app
//     (not the extension)
//   - iOS 16.1+ runtime guard (handled in the bundle declaration)

import ActivityKit
import WidgetKit
import SwiftUI

// Shape shared with the main app — copy this struct into the main app
// target as well so both sides agree on attribute layout.
struct EveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stage: Stage             // thinking | streaming | tool | done
        var headline: String         // "Eve thinking…" / "Creating task" / final reply preview
        var body: String             // partial reply text or tool detail
        var success: Bool
        public enum Stage: String, Codable, Hashable { case thinking, streaming, tool, done }
    }
    var conversationId: String
}

@available(iOS 16.1, *)
struct EveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EveActivityAttributes.self) { context in
            // Lock-screen / banner UI
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: stageIcon(context.state.stage))
                        .foregroundColor(.indigo)
                    Text(context.state.headline)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.indigo)
                }
                Text(context.state.body)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("EVE").font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2).foregroundColor(.indigo)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.body)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)
                }
            } compactLeading: {
                Image(systemName: stageIcon(context.state.stage))
                    .foregroundColor(.indigo)
            } compactTrailing: {
                Text(context.state.headline)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: stageIcon(context.state.stage))
                    .foregroundColor(.indigo)
            }
        }
    }

    private func stageIcon(_ stage: EveActivityAttributes.ContentState.Stage) -> String {
        switch stage {
        case .thinking:  return "brain"
        case .streaming: return "ellipsis.message"
        case .tool:      return "bolt"
        case .done:      return "checkmark.circle"
        }
    }
}
