// BriefingWidget.swift
// Lock Screen + Home Screen widget that shows a one-glance briefing:
// active ops count, agents count, fresh findings count, and last update
// timestamp. No taps needed — calm, ambient.
//
// Data path: the widget extension reads a small JSON snapshot the main
// app writes to a shared App Group container. The main app refreshes
// the snapshot any time it fetches a fresh briefing or a new agent
// finding lands. Widget refresh policy is "after" (every 15 min hint;
// system decides actual cadence).

import WidgetKit
import SwiftUI

// MARK: - Snapshot model (shared across app + extension via App Group)

struct BriefingSnapshot: Codable {
    let updatedAt: Date
    let activeOps: Int
    let activeAgents: Int
    let activeFindings: Int
    let memories: Int
    let latestOpName: String?

    static let empty = BriefingSnapshot(
        updatedAt: Date.distantPast,
        activeOps: 0, activeAgents: 0, activeFindings: 0, memories: 0,
        latestOpName: nil
    )
}

enum BriefingSnapshotStore {
    // The App Group identifier must match what's set on the main app
    // target's entitlement and on this Widget Extension's entitlement.
    static let appGroup = "group.io.talkcircles.nexus"
    static let key      = "briefing.snapshot"

    static func read() -> BriefingSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(BriefingSnapshot.self, from: data)
        else { return .empty }
        return snap
    }

    static func write(_ snap: BriefingSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snap)
        else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: "BriefingWidget")
    }
}

// MARK: - Timeline provider

struct BriefingProvider: TimelineProvider {
    func placeholder(in context: Context) -> BriefingEntry {
        BriefingEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefingEntry) -> Void) {
        completion(BriefingEntry(date: Date(), snapshot: BriefingSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefingEntry>) -> Void) {
        let snap = BriefingSnapshotStore.read()
        let entry = BriefingEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct BriefingEntry: TimelineEntry {
    let date: Date
    let snapshot: BriefingSnapshot
}

// MARK: - Widget views

struct BriefingWidget: Widget {
    let kind = "BriefingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BriefingProvider()) { entry in
            BriefingWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Eve Briefing")
        .description("Active ops, agents, and findings at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct BriefingWidgetView: View {
    let entry: BriefingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.snapshot.activeOps) ops · \(entry.snapshot.activeFindings) new")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(entry.snapshot.activeOps)")
                    .font(.system(size: 22, weight: .bold))
                Text("OPS").font(.system(size: 8, weight: .bold)).tracking(1)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("EVE").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.tint)
                Text("\(entry.snapshot.activeOps) ops · \(entry.snapshot.activeAgents) agents")
                    .font(.system(size: 12, weight: .medium))
                if entry.snapshot.activeFindings > 0 {
                    Text("\(entry.snapshot.activeFindings) findings")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Text("EVE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(.indigo)
                Text("\(entry.snapshot.activeOps)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("active operations")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                Spacer()
                if entry.snapshot.activeFindings > 0 {
                    Text("\(entry.snapshot.activeFindings) new findings")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .padding(12)
        default:
            HStack(spacing: 16) {
                statBlock("OPS", value: entry.snapshot.activeOps)
                statBlock("AGENTS", value: entry.snapshot.activeAgents)
                statBlock("FINDINGS", value: entry.snapshot.activeFindings, accent: .green)
                statBlock("MEMS", value: entry.snapshot.memories)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func statBlock(_ label: String, value: Int, accent: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
