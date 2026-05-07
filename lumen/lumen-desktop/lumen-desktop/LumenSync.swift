// LumenSync.swift
//
// Background sync layer. Keeps Lumen's local store fresh against nexus-web
// (which is itself authoritative against Supabase). Every open window —
// main, panels, detached operations, conversations — sees the same data
// because the store is one place.
//
// Strategy: a single timer-driven refresh loop on the main actor. Different
// data surfaces have different cadences:
//   - Dashboard (agents/ops counts, activity, briefs)        : every 20s
//   - Conversations list (with previews + counts)             : every 45s
//   - Directives + Memory bank                                : every 90s
//   - Nexus Map (only if the map panel was visited this run)  : every 120s
//
// Manual events (NEW conversation, RUN AGENT, etc.) trigger an immediate
// refresh of the affected surface via `kickX()` calls.

import Foundation
import Combine

@MainActor
final class LumenSync: ObservableObject {
    // Defaults — overridable at runtime via UserDefaults so the Settings tab
    // sliders take effect without restarting Lumen. Reads happen on each
    // tick so changes apply immediately.
    static let cadenceFastDefault: TimeInterval = 20    // dashboard
    static let cadenceConvDefault: TimeInterval = 45    // conversation list
    static let cadenceMidDefault:  TimeInterval = 90    // directives + memory
    static let cadenceMapDefault:  TimeInterval = 120   // nexus map

    static var cadenceFast: TimeInterval { cadenceFromDefaults("lumen.cadence.dashboard", fallback: cadenceFastDefault) }
    static var cadenceConv: TimeInterval { cadenceFromDefaults("lumen.cadence.conv",      fallback: cadenceConvDefault) }
    static var cadenceMid:  TimeInterval { cadenceFromDefaults("lumen.cadence.mid",       fallback: cadenceMidDefault) }
    static let cadenceMap:  TimeInterval = 120   // map — fixed, no slider yet

    private static func cadenceFromDefaults(_ key: String, fallback: TimeInterval) -> TimeInterval {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? stored : fallback
    }

    @Published private(set) var lastDashboardSync: Date? = nil
    @Published private(set) var lastConversationsSync: Date? = nil
    @Published private(set) var lastDirectivesMemorySync: Date? = nil
    @Published private(set) var lastMapSync: Date? = nil
    @Published private(set) var isPaused: Bool = false

    private weak var store: LumenStore?
    private var loopTask: Task<Void, Never>? = nil
    private var mapEverFetched: Bool = false

    init(store: LumenStore) {
        self.store = store
    }

    /// Cadence for the LumenLocalDB delta sync. Default 5 min, overridable
    /// via UserDefaults (Settings tab slider).
    static let cadenceLocalDBDefault: TimeInterval = 300
    static var cadenceLocalDB: TimeInterval { cadenceFromDefaults("lumen.cadence.localdb", fallback: cadenceLocalDBDefault) }
    @Published private(set) var lastLocalDBSync: Date? = nil

    /// Begin the periodic loop. Idempotent — multiple calls are safe.
    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            // Initial burst — populate everything so first paint isn't empty.
            await self?.refreshLocalDB()  // SQLite cache fill first so panel paints don't blank-spinner
            await self?.refreshDashboard()
            await self?.refreshConversations()
            await self?.refreshDirectivesAndMemory()

            while let self, !Task.isCancelled {
                let now = Date()
                if Self.due(self.lastDashboardSync, every: Self.cadenceFast, now: now), !self.isPaused {
                    await self.refreshDashboard()
                }
                if Self.due(self.lastConversationsSync, every: Self.cadenceConv, now: now), !self.isPaused {
                    await self.refreshConversations()
                }
                if Self.due(self.lastDirectivesMemorySync, every: Self.cadenceMid, now: now), !self.isPaused {
                    await self.refreshDirectivesAndMemory()
                }
                if self.mapEverFetched, Self.due(self.lastMapSync, every: Self.cadenceMap, now: now), !self.isPaused {
                    await self.refreshMap()
                }
                if Self.due(self.lastLocalDBSync, every: Self.cadenceLocalDB, now: now), !self.isPaused {
                    await self.refreshLocalDB()
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5s tick
            }
        }
    }

    /// User-triggered manual full sync — the "Sync now" toolbar action.
    /// Kicks the LumenLocalDB sync engine immediately and resets the timer.
    func kickLocalDBSync() {
        Task { await refreshLocalDB() }
    }

    private func refreshLocalDB() async {
        _ = await LumenSyncEngine.shared.syncAll()
        lastLocalDBSync = Date()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func pause()  { isPaused = true }
    func resume() { isPaused = false }

    // MARK: - On-demand kickers (called after explicit user actions)

    func kickDashboard() { Task { await refreshDashboard() } }
    func kickConversations() { Task { await refreshConversations() } }
    func kickDirectivesAndMemory() { Task { await refreshDirectivesAndMemory() } }
    func kickMap() { mapEverFetched = true; Task { await refreshMap() } }

    /// Mark map as in-use so the loop starts polling it.
    func mapDidOpen() { mapEverFetched = true }

    // MARK: - Refresh implementations

    private func refreshDashboard() async {
        guard let store else { return }
        await store.fetchDashboard()
        lastDashboardSync = Date()
    }

    private func refreshConversations() async {
        guard let store else { return }
        await store.fetchConversations()
        lastConversationsSync = Date()
    }

    private func refreshDirectivesAndMemory() async {
        guard let store else { return }
        async let d: Void = store.fetchDirectives()
        async let m: Void = store.fetchMemories()
        _ = await (d, m)
        lastDirectivesMemorySync = Date()
    }

    private func refreshMap() async {
        guard let store else { return }
        await store.fetchNexusMap()
        lastMapSync = Date()
    }

    // MARK: - Helpers

    private static func due(_ last: Date?, every: TimeInterval, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= every
    }
}
