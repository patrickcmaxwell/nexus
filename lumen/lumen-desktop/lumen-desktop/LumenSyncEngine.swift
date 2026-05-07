import Foundation
import Combine

// LumenSyncEngine
//
// Pulls deltas from Supabase REST into LumenLocalDB. Per-table watermark
// (`sync_state.last_seen_updated_at`) so each pass only fetches rows
// updated since the previous successful sync — no full-table reloads on
// every refresh.
//
// Why direct Supabase REST (not nexus-web): nexus-web doesn't expose
// delta-by-watermark endpoints — only full lists. Direct REST lets us ask
// `?updated_at=gt.<watermark>` and pull exactly the changed rows. We
// already trust this layer for direct DB access (see SupabaseClient.swift).
//
// Owner-only for now. The userID is hardcoded to Patrick's auth_id; when
// Lumen goes multi-user we'll switch this to read the active human's
// `auth_id` from LumenAuthRegistry instead.
//
// Triggering: LumenStore calls `syncAll()` periodically (every ~5 min) and
// on user-initiated "Sync now". Per-table syncs run sequentially inside
// one pass to keep the SQLite write contention predictable.

@MainActor
final class LumenSyncEngine: ObservableObject {
    static let shared = LumenSyncEngine()

    /// Owner's auth.users.id — same value SupabaseClient hardcodes today.
    /// When Lumen goes multi-user, swap this for the active human's auth_id.
    private let userID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

    private let baseURL = "https://rtkzvsqulliaoizutsqz.supabase.co"
    private let apiKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0a3p2c3F1bGxpYW9penV0c3F6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTYxNzM0MSwiZXhwIjoyMDkxMTkzMzQxfQ.OMRaTWkHQe_9RufUU6MloYAwdw9kPmIPAraKDINioBs"

    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastFullSyncAt: Date? = nil
    @Published private(set) var lastSyncError: String? = nil

    private var rest: String { "\(baseURL)/rest/v1" }

    private func headers() -> [String: String] {
        return [
            "apikey":        apiKey,
            "Authorization": "Bearer \(apiKey)",
            "Content-Type":  "application/json",
        ]
    }

    // MARK: - Public surface

    /// Tombstone reconcile pass runs at most once per hour per table.
    /// Catches server-side deletes that the delta-only sync can't see.
    static let reconcileCadence: TimeInterval = 3600

    /// How many recent conversations to background-fill messages for on each
    /// pass. Trade-off: more = wider offline coverage, slower per-pass cost.
    /// 10 is a tight-but-useful default (today's actively-used threads).
    static let messageBackfillTopN = 10

    /// Run a full delta sync across every cached table. Sequential per
    /// table so we don't slam SQLite. Also runs an hourly reconcile pass
    /// to evict tombstoned rows. Returns the number of rows applied.
    @discardableResult
    func syncAll() async -> Int {
        guard !isSyncing else { return 0 }
        isSyncing = true
        defer { isSyncing = false }
        lastSyncError = nil

        var total = 0
        do {
            // Push optimistic writes BEFORE pulling deltas — that way a row
            // we created locally but couldn't push lands on the server in
            // time for the delta query to see it (otherwise it'd come back
            // marked-pending forever).
            await retryPendingConversations()
            total += try await syncConversations()
            total += try await syncOperations()
            total += try await syncRecords()
            total += try await syncAgents()
            total += try await syncDirectives()
            total += try await syncMemories()
            // Backfill messages for the top N most-recent conversations so
            // opening any of them is instant. Runs after syncConversations
            // so the cache has the latest list to pull from.
            await backfillRecentConversationMessages(limit: Self.messageBackfillTopN)
            // Reconcile catches server-side deletes that the delta sync
            // can't see (delta only INSERTs). Once an hour is plenty —
            // most data lives long enough that ghost rows aren't a crisis.
            await reconcileIfDue()
            lastFullSyncAt = Date()
        } catch {
            lastSyncError = (error as NSError).localizedDescription
        }
        return total
    }

    /// Retry server-side creates for conversations that were optimistically
    /// written locally but whose initial server push failed (offline, server
    /// down, etc.). Idempotent — `createConversation` with an explicitId is
    /// safe to call multiple times because the server uses upsert semantics
    /// on primary key conflict via Supabase's default `prefer: resolution=merge`.
    private func retryPendingConversations() async {
        let pending = await LumenLocalDB.shared.pendingSyncConversations()
        guard !pending.isEmpty else { return }
        for row in pending {
            let result = await SupabaseClient.shared.createConversation(
                title: row.title,
                source: row.source,
                explicitId: row.id
            )
            if result != nil {
                await LumenLocalDB.shared.markConversationPendingSync(id: row.id, pending: false)
            }
        }
    }

    /// Background-fill messages for the top N most-recent conversations.
    /// Lets the user open any of them cold without a network round-trip.
    /// Cheap because we read the conversation list from local cache (post
    /// syncConversations) rather than re-querying the server, and we use
    /// the existing per-conversation messages endpoint for content.
    ///
    /// Skip cost: we always fetch + replace. Per-conversation message
    /// counts are small (typically <200 rows) and the network call is the
    /// dominant cost — adding a count-probe round-trip wouldn't actually
    /// save time on cache hits, just wire complexity.
    private func backfillRecentConversationMessages(limit: Int) async {
        let recent = await LumenLocalDB.shared.fetchConversations(limit: limit)
        guard !recent.isEmpty else { return }

        // Sequential rather than parallel: SupabaseClient hits a single
        // backend, and we want predictable bandwidth + don't want to flood
        // SQLite with concurrent writes.
        for conv in recent {
            let msgs = await SupabaseClient.shared.fetchMessages(conversationId: conv.id)
            guard !msgs.isEmpty else { continue }
            let rows = msgs.map { msg in
                LumenLocalDB.MessageRow(
                    role: msg.role == .user ? "user" : "assistant",
                    content: msg.content,
                    createdAt: nil
                )
            }
            await LumenLocalDB.shared.replaceMessages(conversationId: conv.id, messages: rows)
        }
    }

    /// Force a reconcile NOW regardless of the cadence. Surfaced via the
    /// "Reconcile" button (when we add it) for users who suspect the cache
    /// is showing ghosts.
    @discardableResult
    func reconcileAll() async -> Int {
        var deleted = 0
        deleted += (try? await reconcile(table: "conversations",     remoteTable: "eve_conversations")) ?? 0
        deleted += (try? await reconcile(table: "operations",        remoteTable: "operations"))         ?? 0
        deleted += (try? await reconcile(table: "operation_records", remoteTable: "operation_records")) ?? 0
        deleted += (try? await reconcile(table: "agents",            remoteTable: "agents"))             ?? 0
        deleted += (try? await reconcile(table: "directives",        remoteTable: "eve_directives"))     ?? 0
        deleted += (try? await reconcile(table: "memories",          remoteTable: "eve_memory"))         ?? 0
        return deleted
    }

    private func reconcileIfDue() async {
        let pairs: [(local: String, remote: String)] = [
            ("conversations",     "eve_conversations"),
            ("operations",        "operations"),
            ("operation_records", "operation_records"),
            ("agents",            "agents"),
            ("directives",        "eve_directives"),
            ("memories",          "eve_memory"),
        ]
        for p in pairs {
            let last = await LumenLocalDB.shared.lastReconciledAt(for: p.local)
            if let last, Date().timeIntervalSince(last) < Self.reconcileCadence { continue }
            _ = try? await reconcile(table: p.local, remoteTable: p.remote)
        }
    }

    /// Fetch every server id for `remoteTable` and delete cached rows in
    /// `table` whose ids are missing from that set. `select=id` is the
    /// cheapest possible Supabase query.
    @discardableResult
    private func reconcile(table: String, remoteTable: String) async throws -> Int {
        var components = URLComponents(string: "\(rest)/\(remoteTable)")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "limit", value: "10000"),
        ]
        guard let url = components.url else { return 0 }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.allHTTPHeaderFields = headers()

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return 0 }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return 0 }
        let serverIds = Set(arr.compactMap { $0["id"] as? String })

        let cachedIds = await LumenLocalDB.shared.cachedIds(in: table)
        let toDelete = cachedIds.subtracting(serverIds)
        if !toDelete.isEmpty {
            await LumenLocalDB.shared.deleteRows(in: table, ids: toDelete)
        }
        await LumenLocalDB.shared.setLastReconciledAt(for: table)
        return toDelete.count
    }

    // MARK: - Per-table sync

    @discardableResult
    func syncConversations() async throws -> Int {
        let table = "conversations"
        let watermark = await LumenLocalDB.shared.lastSeenUpdatedAt(for: table)
        let rows = try await fetchDelta(
            from: "eve_conversations",
            select: "id,user_id,title,source,created_at,updated_at",
            sinceWatermark: watermark
        )
        let mapped: [LumenLocalDB.ConversationRow] = rows.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let title = d["title"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.ConversationRow(
                id: id, userId: userId, title: title,
                source: d["source"] as? String ?? "lumen",
                createdAt: d["created_at"] as? String ?? updatedAt,
                updatedAt: updatedAt,
                preview: "",       // preview/count come from the nexus-web augmented endpoint, not raw table
                messageCount: 0
            )
        }
        await LumenLocalDB.shared.upsertConversations(mapped)
        await LumenLocalDB.shared.setSyncState(
            for: table,
            lastSeenUpdatedAt: maxUpdatedAt(rows: rows, fallback: watermark)
        )
        return mapped.count
    }

    @discardableResult
    func syncOperations() async throws -> Int {
        let table = "operations"
        let watermark = await LumenLocalDB.shared.lastSeenUpdatedAt(for: table)
        let rows = try await fetchDelta(
            from: "operations",
            select: "id,user_id,name,codename,status,priority,description,directives,created_at,updated_at",
            sinceWatermark: watermark
        )
        let mapped: [LumenLocalDB.OperationRow] = rows.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let name = d["name"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.OperationRow(
                id: id, userId: userId, name: name,
                codename: d["codename"] as? String,
                status: d["status"] as? String ?? "active",
                priority: d["priority"] as? String ?? "medium",
                description: d["description"] as? String,
                directives: d["directives"] as? String,
                updatedAt: updatedAt,
                createdAt: d["created_at"] as? String ?? updatedAt
            )
        }
        await LumenLocalDB.shared.upsertOperations(mapped)
        await LumenLocalDB.shared.setSyncState(
            for: table,
            lastSeenUpdatedAt: maxUpdatedAt(rows: rows, fallback: watermark)
        )
        return mapped.count
    }

    @discardableResult
    func syncRecords() async throws -> Int {
        let table = "operation_records"
        let watermark = await LumenLocalDB.shared.lastSeenUpdatedAt(for: table)
        let rows = try await fetchDelta(
            from: "operation_records",
            select: "id,operation_id,user_id,type,title,content,status,priority,pinned,archived_at,created_at,updated_at",
            sinceWatermark: watermark
        )
        let mapped: [LumenLocalDB.RecordRow] = rows.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let type = d["type"] as? String,
                  let title = d["title"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.RecordRow(
                id: id,
                operationId: d["operation_id"] as? String,
                userId: userId,
                type: type,
                title: title,
                content: d["content"] as? String,
                status: d["status"] as? String,
                priority: d["priority"] as? String ?? "normal",
                pinned: (d["pinned"] as? Bool) ?? false,
                archivedAt: d["archived_at"] as? String,
                createdAt: d["created_at"] as? String ?? updatedAt,
                updatedAt: updatedAt
            )
        }
        await LumenLocalDB.shared.upsertRecords(mapped)
        await LumenLocalDB.shared.setSyncState(
            for: table,
            lastSeenUpdatedAt: maxUpdatedAt(rows: rows, fallback: watermark)
        )
        return mapped.count
    }

    @discardableResult
    func syncAgents() async throws -> Int {
        let table = "agents"
        let watermark = await LumenLocalDB.shared.lastSeenUpdatedAt(for: table)
        let rows = try await fetchDelta(
            from: "agents",
            select: "id,user_id,name,codename,role,status,total_findings,last_scanned_at,created_at,updated_at",
            sinceWatermark: watermark
        )
        let mapped: [LumenLocalDB.AgentRow] = rows.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let name = d["name"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.AgentRow(
                id: id, userId: userId, name: name,
                codename: d["codename"] as? String,
                role: d["role"] as? String ?? "analyst",
                status: d["status"] as? String ?? "standby",
                totalFindings: (d["total_findings"] as? Int) ?? 0,
                lastScannedAt: d["last_scanned_at"] as? String,
                createdAt: d["created_at"] as? String ?? updatedAt,
                updatedAt: updatedAt
            )
        }
        await LumenLocalDB.shared.upsertAgents(mapped)
        await LumenLocalDB.shared.setSyncState(
            for: table,
            lastSeenUpdatedAt: maxUpdatedAt(rows: rows, fallback: watermark)
        )
        return mapped.count
    }

    @discardableResult
    func syncDirectives() async throws -> Int {
        let table = "directives"
        let watermark = await LumenLocalDB.shared.lastSeenUpdatedAt(for: table)
        let rows = try await fetchDelta(
            from: "eve_directives",
            select: "id,user_id,type,title,content,is_active,priority,target,updated_at",
            sinceWatermark: watermark
        )
        let mapped: [LumenLocalDB.DirectiveRow] = rows.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let type = d["type"] as? String,
                  let title = d["title"] as? String,
                  let content = d["content"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.DirectiveRow(
                id: id, userId: userId, type: type,
                title: title, content: content,
                isActive: (d["is_active"] as? Bool) ?? true,
                priority: (d["priority"] as? Int) ?? 0,
                target: d["target"] as? String,
                updatedAt: updatedAt
            )
        }
        await LumenLocalDB.shared.upsertDirectives(mapped)
        await LumenLocalDB.shared.setSyncState(
            for: table,
            lastSeenUpdatedAt: maxUpdatedAt(rows: rows, fallback: watermark)
        )
        return mapped.count
    }

    @discardableResult
    func syncMemories() async throws -> Int {
        let table = "memories"
        let watermark = await LumenLocalDB.shared.lastSeenUpdatedAt(for: table)
        let rows = try await fetchDelta(
            from: "eve_memory",
            select: "id,user_id,type,content,source,is_active,priority,updated_at",
            sinceWatermark: watermark
        )
        let mapped: [LumenLocalDB.MemoryRow] = rows.compactMap { d in
            guard let id = d["id"] as? String,
                  let userId = d["user_id"] as? String,
                  let type = d["type"] as? String,
                  let content = d["content"] as? String,
                  let updatedAt = d["updated_at"] as? String else { return nil }
            return LumenLocalDB.MemoryRow(
                id: id, userId: userId, type: type,
                content: content,
                source: d["source"] as? String,
                isActive: (d["is_active"] as? Bool) ?? true,
                priority: (d["priority"] as? Int) ?? 5,
                updatedAt: updatedAt
            )
        }
        await LumenLocalDB.shared.upsertMemories(mapped)
        await LumenLocalDB.shared.setSyncState(
            for: table,
            lastSeenUpdatedAt: maxUpdatedAt(rows: rows, fallback: watermark)
        )
        return mapped.count
    }

    // MARK: - Plumbing

    /// Fetch rows from `table` whose `updated_at` is greater than the
    /// watermark. Returns up to 500 rows per call — enough to handle a
    /// missed-day-of-activity catch-up, without unbounded memory.
    private func fetchDelta(
        from table: String,
        select: String,
        sinceWatermark watermark: String?,
        limit: Int = 500
    ) async throws -> [[String: Any]] {
        var components = URLComponents(string: "\(rest)/\(table)")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "order", value: "updated_at.asc"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let watermark, !watermark.isEmpty {
            items.append(URLQueryItem(name: "updated_at", value: "gt.\(watermark)"))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw NSError(domain: "LumenSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad URL for \(table)"])
        }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.allHTTPHeaderFields = headers()

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "LumenSync", code: code, userInfo: [
                NSLocalizedDescriptionKey: "\(table) sync HTTP \(code): \(body.prefix(200))"
            ])
        }

        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    /// Pick the highest `updated_at` from the returned rows so the next
    /// sync's watermark advances. If the response was empty we keep the
    /// previous watermark so we don't silently rewind.
    private func maxUpdatedAt(rows: [[String: Any]], fallback: String?) -> String? {
        var hi = fallback
        for r in rows {
            guard let ts = r["updated_at"] as? String else { continue }
            if hi == nil || ts > hi! { hi = ts }
        }
        return hi
    }
}
