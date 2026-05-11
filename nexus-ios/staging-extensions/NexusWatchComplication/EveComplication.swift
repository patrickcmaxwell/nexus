// EveComplication.swift
// watchOS complication — single-tap launches Eve from the watch face.
// Lives inside the existing Watch App target (no separate extension is
// needed on watchOS 10+; SwiftUI Widgets can be embedded directly).
//
// Add this file to the "nexus-watch Watch App" target in Xcode. The
// Watch app's @main App now needs to also expose a WidgetBundle — see
// the snippet below.
//
//   // In nexus_watchApp.swift:
//   @main
//   struct NexusWatchAppBundle: WidgetBundle {
//       var body: some Widget { EveComplication() }
//   }
//   // Then keep the existing App in a separate file with its own
//   // @main? No — only one @main per target. Use a single bundle that
//   // wraps both the App and the Widget at scene level.
//
// Simpler: drop @main from nexus_watchApp.swift and use this single
// @main that wraps both. See WatchEntry.swift in this folder.

import WidgetKit
import SwiftUI

struct EveComplicationEntry: TimelineEntry {
    let date: Date
}

struct EveComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> EveComplicationEntry {
        EveComplicationEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (EveComplicationEntry) -> Void) {
        completion(EveComplicationEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EveComplicationEntry>) -> Void) {
        // The complication is a launcher, not a data view — single entry,
        // refreshed on a casual cadence.
        let entry = EveComplicationEntry(date: Date())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct EveComplication: Widget {
    let kind = "EveComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EveComplicationProvider()) { _ in
            EveComplicationView()
        }
        .configurationDisplayName("Eve")
        .description("Tap to talk to Eve")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct EveComplicationView: View {
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Talk to Eve")
        case .accessoryCircular:
            ZStack {
                Circle().fill(Color.indigo.opacity(0.18))
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.indigo)
            }
        case .accessoryCorner:
            Image(systemName: "sparkles")
                .widgetCurvesContent()
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundColor(.indigo)
                VStack(alignment: .leading, spacing: 0) {
                    Text("EVE").font(.system(size: 9, weight: .bold)).tracking(1.5)
                    Text("Tap to talk").font(.system(size: 11))
                }
            }
        default:
            Image(systemName: "sparkles")
        }
    }
}
