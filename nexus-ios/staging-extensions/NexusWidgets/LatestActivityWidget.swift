// LatestActivityWidget.swift
// Glance widget that shows the most recent thing Eve actually did via
// Arena — task created, payment routed, sync pushed, etc. Same App Group
// snapshot pattern as BriefingWidget.

import WidgetKit
import SwiftUI

struct LatestActivitySnapshot: Codable {
    let updatedAt: Date
    let action: String        // "arena_task_create"
    let label: String         // "Created task"
    let primary: String       // "Draft Q3 plan"
    let detail: String        // task id, status, etc.
    let success: Bool

    static let empty = LatestActivitySnapshot(
        updatedAt: Date.distantPast,
        action: "",
        label: "Eve has been quiet.",
        primary: "",
        detail: "",
        success: true
    )
}

enum LatestActivityStore {
    static let appGroup = BriefingSnapshotStore.appGroup
    static let key      = "latestActivity.snapshot"

    static func read() -> LatestActivitySnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(LatestActivitySnapshot.self, from: data)
        else { return .empty }
        return snap
    }

    static func write(_ snap: LatestActivitySnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snap)
        else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: "LatestActivityWidget")
    }
}

struct LatestActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestActivityEntry {
        LatestActivityEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (LatestActivityEntry) -> Void) {
        completion(LatestActivityEntry(date: Date(), snapshot: LatestActivityStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestActivityEntry>) -> Void) {
        let entry = LatestActivityEntry(date: Date(), snapshot: LatestActivityStore.read())
        let next = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date().addingTimeInterval(600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct LatestActivityEntry: TimelineEntry {
    let date: Date
    let snapshot: LatestActivitySnapshot
}

struct LatestActivityWidget: Widget {
    let kind = "LatestActivityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestActivityProvider()) { entry in
            LatestActivityView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Latest Eve action")
        .description("The last thing Eve did — task, payment, sync, or audit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct LatestActivityView: View {
    let entry: LatestActivityEntry
    @Environment(\.widgetFamily) var family
    private var iconName: String {
        switch entry.snapshot.action {
        case let s where s.contains("task"):    return "checklist"
        case let s where s.contains("payment"): return "dollarsign.circle"
        case let s where s.contains("sync"):    return "arrow.triangle.2.circlepath"
        case let s where s.contains("recent"):  return "clock"
        default:                                return "bolt"
        }
    }
    private var accent: Color { entry.snapshot.success ? .green : .red }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.snapshot.label): \(entry.snapshot.primary)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: iconName).font(.system(size: 10))
                    Text(entry.snapshot.label).font(.system(size: 10, weight: .bold))
                }
                Text(entry.snapshot.primary).font(.system(size: 12)).lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: iconName).foregroundColor(accent)
                    Text(entry.snapshot.label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.6))
                }
                Text(entry.snapshot.primary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(family == .systemSmall ? 3 : 2)
                if !entry.snapshot.detail.isEmpty {
                    Text(entry.snapshot.detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
        }
    }
}
