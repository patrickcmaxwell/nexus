import Foundation
import SQLite3

// LumenLocalDB
//
// Single-user SQLite cache that mirrors the subset of nexus-web tables Lumen
// actually shows. Read-from-cache-first means panel switches paint instantly
// instead of waiting on the network; the sync engine fills/updates rows in
// the background and the store re-renders.
//
// Why direct sqlite3 (not GRDB / SwiftData):
//   - Zero new project deps. No SPM round-trip in Xcode for Patrick.
//   - macOS bundles libsqlite3 forever — never breaks on OS upgrades.
//   - The schema is small + write-mostly-by-sync; we don't need ORM magic.
//
// Threading: actor isolation handles concurrency. All public methods are
// async. The underlying `sqlite3*` handle is opened with FULLMUTEX so even
// if it leaks across actor isolation it stays safe.
//
// Storage location: ~/Library/Application Support/Lumen/lumen.sqlite
//   - Co-located with the existing session_cache.json so we have one Lumen
//     data folder users can blow away to "reset offline state."
//
// Schema migrations: incrementing `schema_version` PRAGMA. Each migration
// runs in order on first open after upgrade. Adding a new column = add a
// new step; dropping data = explicit DROP/RECREATE in a new step.

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor LumenLocalDB {
    static let shared = LumenLocalDB()

    private var db: OpaquePointer?
    private var openErrorMessage: String?

    /// Mirrors the subset of public.eve_conversations Lumen renders.
    struct ConversationRow: Sendable {
        let id: String
        let userId: String
        let title: String
        let source: String
        let createdAt: String   // ISO8601 timestamp from server
        let updatedAt: String
        let preview: String
        let messageCount: Int
    }

    /// Mirrors the subset of public.operations Lumen renders.
    struct OperationRow: Sendable {
        let id: String
        let userId: String
        let name: String
        let codename: String?
        let status: String
        let priority: String
        let description: String?
        let directives: String?
        let updatedAt: String
        let createdAt: String
    }

    /// Mirrors the subset of public.operation_records Lumen renders.
    struct RecordRow: Sendable {
        let id: String
        let operationId: String?
        let userId: String
        let type: String
        let title: String
        let content: String?
        let status: String?
        let priority: String
        let pinned: Bool
        let archivedAt: String?
        let createdAt: String
        let updatedAt: String
    }

    /// Mirrors the subset of public.agents Lumen renders.
    struct AgentRow: Sendable {
        let id: String
        let userId: String
        let name: String
        let codename: String?
        let role: String
        let status: String
        let totalFindings: Int
        let lastScannedAt: String?
        let createdAt: String
        let updatedAt: String
    }

    /// Mirrors the subset of public.eve_directives Lumen renders.
    struct DirectiveRow: Sendable {
        let id: String
        let userId: String
        let type: String
        let title: String
        let content: String
        let isActive: Bool
        let priority: Int
        let target: String?
        let updatedAt: String
    }

    /// Mirrors the subset of public.eve_memory Lumen renders.
    struct MemoryRow: Sendable {
        let id: String
        let userId: String
        let type: String
        let content: String
        let source: String?
        let isActive: Bool
        let priority: Int
        let updatedAt: String
    }

    init() {
        openDatabase()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Public surface

    /// True once the underlying SQLite file is open and migrations have run.
    /// Useful for the System panel's "Local DB: ready / not ready" indicator.
    func isReady() -> Bool { db != nil }

    /// Surfaces the last open error (file path conflict, disk full, etc.) so
    /// the System panel can show why we're falling back to network-only mode.
    func lastOpenError() -> String? { openErrorMessage }

    /// On-disk path of the SQLite file — surfaced in the System panel so
    /// power users can find / inspect / nuke it.
    nonisolated static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lumen", isDirectory: true)
            .appendingPathComponent("lumen.sqlite")
    }

    /// Total bytes the SQLite file occupies on disk. -1 if not measurable yet.
    nonisolated static var fileSizeBytes: Int64 {
        guard let url = fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return -1 }
        return size.int64Value
    }

    // MARK: - Sync watermark (per table)

    /// The newest `updated_at` we've already pulled for `table`. The sync
    /// engine queries `?updated_at=gt.{this}` to fetch only deltas.
    func lastSeenUpdatedAt(for table: String) -> String? {
        let rows = query("SELECT last_seen_updated_at FROM sync_state WHERE table_name = ?", params: [table])
        return (rows.first?["last_seen_updated_at"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Update the watermark + last-synced-at after a successful sync pass.
    func setSyncState(for table: String, lastSeenUpdatedAt: String?, syncedAt: Date = Date()) {
        let iso = isoFormatter.string(from: syncedAt)
        exec("""
        INSERT INTO sync_state (table_name, last_seen_updated_at, last_synced_at)
        VALUES (?, ?, ?)
        ON CONFLICT(table_name) DO UPDATE SET
            last_seen_updated_at = COALESCE(excluded.last_seen_updated_at, sync_state.last_seen_updated_at),
            last_synced_at       = excluded.last_synced_at
        """, params: [table, lastSeenUpdatedAt as Any?, iso])
    }

    /// Last successful sync time for `table`, or nil if never synced this install.
    func lastSyncedAt(for table: String) -> Date? {
        let rows = query("SELECT last_synced_at FROM sync_state WHERE table_name = ?", params: [table])
        guard let str = rows.first?["last_synced_at"] as? String, !str.isEmpty else { return nil }
        return isoFormatter.date(from: str)
    }

    /// All known sync_state rows — feeds the "Datasets" view in the System panel.
    func allSyncStates() -> [(table: String, lastSyncedAt: Date?, lastSeen: String?)] {
        let rows = query("SELECT table_name, last_synced_at, last_seen_updated_at FROM sync_state ORDER BY table_name", params: [])
        return rows.compactMap { r in
            guard let name = r["table_name"] as? String else { return nil }
            let synced = (r["last_synced_at"] as? String).flatMap(isoFormatter.date(from:))
            let seen = r["last_seen_updated_at"] as? String
            return (name, synced, seen)
        }
    }

    /// Row counts per cached table — same datasource as above.
    func tableRowCounts() -> [(table: String, rows: Int)] {
        let tables = ["conversations", "messages", "operations", "operation_records", "agents", "directives", "memories"]
        return tables.map { name in
            let rows = query("SELECT COUNT(*) AS c FROM \(name)", params: [])
            let count = (rows.first?["c"] as? Int64).map(Int.init) ?? 0
            return (name, count)
        }
    }

    /// Drop every cached table (keeps schema, resets watermarks). Used by
    /// "Reset local cache" in the System panel.
    func resetCache() {
        let tables = ["conversations", "messages", "operations", "operation_records", "agents", "directives", "memories", "sync_state"]
        for t in tables { exec("DELETE FROM \(t)", params: []) }
    }

    /// All cached primary-key ids for `table`. Used by the reconcile pass
    /// to compare against the server's authoritative id set so we can
    /// tombstone rows that vanished server-side (delta sync only INSERTs;
    /// it can't see deletions).
    func cachedIds(in table: String) -> Set<String> {
        let rows = query("SELECT id FROM \(table)", params: [])
        return Set(rows.compactMap { $0["id"] as? String })
    }

    /// Drop the listed ids from `table`. Cascades to dependent tables via
    /// foreign keys (e.g. deleting a conversation cleans its messages).
    func deleteRows(in table: String, ids: Set<String>) {
        guard !ids.isEmpty else { return }
        beginTransaction()
        defer { commitTransaction() }
        // Chunk to keep the SQL under SQLITE_LIMIT_VARIABLE_NUMBER (default 999)
        for chunk in stride(from: 0, to: ids.count, by: 500).map({
            Array(ids).dropFirst($0).prefix(500)
        }) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            exec("DELETE FROM \(table) WHERE id IN (\(placeholders))", params: Array(chunk).map { $0 as Any? })
        }
    }

    /// When did we last run the full id-reconcile (tombstone) pass for
    /// `table`? Stored in sync_state under a separate column so it can
    /// progress independently of the watermark.
    func lastReconciledAt(for table: String) -> Date? {
        let rows = query("SELECT last_reconciled_at FROM sync_state WHERE table_name = ?", params: [table])
        guard let str = rows.first?["last_reconciled_at"] as? String, !str.isEmpty else { return nil }
        return isoFormatter.date(from: str)
    }

    func setLastReconciledAt(for table: String, value: Date = Date()) {
        let iso = isoFormatter.string(from: value)
        // sync_state row may not exist yet — use UPSERT so we don't depend
        // on a separate watermark write happening first.
        exec("""
        INSERT INTO sync_state (table_name, last_synced_at, last_reconciled_at)
        VALUES (?, ?, ?)
        ON CONFLICT(table_name) DO UPDATE SET last_reconciled_at = excluded.last_reconciled_at
        """, params: [table, iso, iso])
    }

    // MARK: - Conversations

    func upsertConversations(_ rows: [ConversationRow]) {
        guard !rows.isEmpty else { return }
        beginTransaction()
        defer { commitTransaction() }
        for row in rows {
            exec("""
            INSERT INTO conversations (id, user_id, title, source, created_at, updated_at, preview, message_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title         = excluded.title,
                source        = excluded.source,
                updated_at    = excluded.updated_at,
                preview       = excluded.preview,
                message_count = excluded.message_count
            """, params: [row.id, row.userId, row.title, row.source, row.createdAt, row.updatedAt, row.preview, row.messageCount])
        }
    }

    func fetchConversations(limit: Int = 60) -> [ConversationRow] {
        let rows = query("""
        SELECT id, user_id, title, source, created_at, updated_at, preview, message_count
        FROM conversations
        ORDER BY datetime(updated_at) DESC
        LIMIT ?
        """, params: [limit])
        return rows.compactMap { r in
            guard let id = r["id"] as? String,
                  let userId = r["user_id"] as? String,
                  let title = r["title"] as? String,
                  let updatedAt = r["updated_at"] as? String else { return nil }
            return ConversationRow(
                id: id,
                userId: userId,
                title: title,
                source: r["source"] as? String ?? "lumen",
                createdAt: r["created_at"] as? String ?? "",
                updatedAt: updatedAt,
                preview: r["preview"] as? String ?? "",
                messageCount: (r["message_count"] as? Int64).map(Int.init) ?? 0
            )
        }
    }

    func deleteConversation(id: String) {
        exec("DELETE FROM conversations WHERE id = ?", params: [id])
        exec("DELETE FROM messages WHERE conversation_id = ?", params: [id])
    }

    // MARK: - Optimistic-write retry

    /// Mark an optimistically-written conversation row as needing a server
    /// retry. Called when the background create fails so the next sync pass
    /// can pick it up.
    func markConversationPendingSync(id: String, pending: Bool = true) {
        exec("UPDATE conversations SET pending_sync = ? WHERE id = ?", params: [pending ? 1 : 0, id])
    }

    /// Conversations whose server-side create never succeeded. The sync
    /// engine retries them on every pass until they land or the user
    /// deletes them.
    func pendingSyncConversations() -> [ConversationRow] {
        let rows = query("""
        SELECT id, user_id, title, source, created_at, updated_at, preview, message_count
        FROM conversations WHERE pending_sync = 1
        """, params: [])
        return rows.compactMap { r in
            guard let id = r["id"] as? String,
                  let userId = r["user_id"] as? String,
                  let title = r["title"] as? String,
                  let updatedAt = r["updated_at"] as? String else { return nil }
            return ConversationRow(
                id: id, userId: userId, title: title,
                source: r["source"] as? String ?? "lumen",
                createdAt: r["created_at"] as? String ?? updatedAt,
                updatedAt: updatedAt,
                preview: r["preview"] as? String ?? "",
                messageCount: (r["message_count"] as? Int64).map(Int.init) ?? 0
            )
        }
    }

    // MARK: - Messages (per-conversation cache)

    /// One row per stored message. We cache by full overwrite of a
    /// conversation's messages — easier than per-row dedup with no server
    /// `id` field, and message lists are small enough that a wipe-and-fill
    /// stays fast.
    struct MessageRow: Sendable {
        let role: String        // "user" | "assistant"
        let content: String
        let createdAt: String?  // optional; we synthesize order if nil
    }

    /// Replace the cached messages for a conversation atomically. Used by
    /// LumenStore.loadConversation after a successful remote fetch so the
    /// next open paints from cache instantly.
    func replaceMessages(conversationId: String, messages: [MessageRow]) {
        beginTransaction()
        defer { commitTransaction() }
        exec("DELETE FROM messages WHERE conversation_id = ?", params: [conversationId])
        for (idx, m) in messages.enumerated() {
            // Synthetic id keeps insert order stable on read since we sort
            // by created_at then by id. Format: "<conv>:<idx>".
            let id = "\(conversationId):\(idx)"
            let createdAt = m.createdAt ?? syntheticTimestamp(forIndex: idx)
            exec("""
            INSERT INTO messages (id, conversation_id, role, content, created_at)
            VALUES (?, ?, ?, ?, ?)
            """, params: [id, conversationId, m.role, m.content, createdAt])
        }
    }

    /// Read the cached messages for a conversation in chronological order.
    /// Empty when the conversation has never been opened (first load hits
    /// the network and the result lands in the cache for next time).
    func fetchMessages(conversationId: String) -> [MessageRow] {
        let rows = query("""
        SELECT role, content, created_at
        FROM messages
        WHERE conversation_id = ?
        ORDER BY datetime(created_at) ASC, id ASC
        """, params: [conversationId])
        return rows.compactMap { r in
            guard let role = r["role"] as? String,
                  let content = r["content"] as? String else { return nil }
            return MessageRow(role: role, content: content, createdAt: r["created_at"] as? String)
        }
    }

    /// True if any messages have been cached for this conversation. Lets the
    /// store skip the cache-paint step when it would be empty anyway.
    func hasCachedMessages(conversationId: String) -> Bool {
        let rows = query("SELECT 1 FROM messages WHERE conversation_id = ? LIMIT 1", params: [conversationId])
        return !rows.isEmpty
    }

    /// Build a sortable timestamp when the server didn't give us one. Each
    /// index gets a slot one second apart so the SQLite ORDER BY is stable.
    private func syntheticTimestamp(forIndex idx: Int) -> String {
        // Anchor to a fixed past date so synthetic timestamps don't mingle
        // with real ones if we later get a mix.
        let anchor = Date(timeIntervalSince1970: 0).addingTimeInterval(TimeInterval(idx))
        return isoFormatter.string(from: anchor)
    }

    // MARK: - Operations

    func upsertOperations(_ rows: [OperationRow]) {
        guard !rows.isEmpty else { return }
        beginTransaction(); defer { commitTransaction() }
        for row in rows {
            exec("""
            INSERT INTO operations (id, user_id, name, codename, status, priority, description, directives, updated_at, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name        = excluded.name,
                codename    = excluded.codename,
                status      = excluded.status,
                priority    = excluded.priority,
                description = excluded.description,
                directives  = excluded.directives,
                updated_at  = excluded.updated_at
            """, params: [row.id, row.userId, row.name, row.codename as Any?, row.status, row.priority, row.description as Any?, row.directives as Any?, row.updatedAt, row.createdAt])
        }
    }

    func fetchOperations(limit: Int = 100) -> [OperationRow] {
        let rows = query("""
        SELECT id, user_id, name, codename, status, priority, description, directives, updated_at, created_at
        FROM operations ORDER BY datetime(updated_at) DESC LIMIT ?
        """, params: [limit])
        return rows.compactMap { r in
            guard let id = r["id"] as? String,
                  let userId = r["user_id"] as? String,
                  let name = r["name"] as? String,
                  let updatedAt = r["updated_at"] as? String else { return nil }
            return OperationRow(
                id: id, userId: userId, name: name,
                codename: r["codename"] as? String,
                status: r["status"] as? String ?? "active",
                priority: r["priority"] as? String ?? "medium",
                description: r["description"] as? String,
                directives: r["directives"] as? String,
                updatedAt: updatedAt,
                createdAt: r["created_at"] as? String ?? updatedAt
            )
        }
    }

    // MARK: - Operation records

    func upsertRecords(_ rows: [RecordRow]) {
        guard !rows.isEmpty else { return }
        beginTransaction(); defer { commitTransaction() }
        for row in rows {
            exec("""
            INSERT INTO operation_records (id, operation_id, user_id, type, title, content, status, priority, pinned, archived_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                operation_id = excluded.operation_id,
                type         = excluded.type,
                title        = excluded.title,
                content      = excluded.content,
                status       = excluded.status,
                priority     = excluded.priority,
                pinned       = excluded.pinned,
                archived_at  = excluded.archived_at,
                updated_at   = excluded.updated_at
            """, params: [row.id, row.operationId as Any?, row.userId, row.type, row.title, row.content as Any?, row.status as Any?, row.priority, row.pinned ? 1 : 0, row.archivedAt as Any?, row.createdAt, row.updatedAt])
        }
    }

    // MARK: - Agents

    func upsertAgents(_ rows: [AgentRow]) {
        guard !rows.isEmpty else { return }
        beginTransaction(); defer { commitTransaction() }
        for row in rows {
            exec("""
            INSERT INTO agents (id, user_id, name, codename, role, status, total_findings, last_scanned_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name           = excluded.name,
                codename       = excluded.codename,
                role           = excluded.role,
                status         = excluded.status,
                total_findings = excluded.total_findings,
                last_scanned_at= excluded.last_scanned_at,
                updated_at     = excluded.updated_at
            """, params: [row.id, row.userId, row.name, row.codename as Any?, row.role, row.status, row.totalFindings, row.lastScannedAt as Any?, row.createdAt, row.updatedAt])
        }
    }

    func fetchAgents(limit: Int = 100) -> [AgentRow] {
        let rows = query("""
        SELECT id, user_id, name, codename, role, status, total_findings, last_scanned_at, created_at, updated_at
        FROM agents ORDER BY datetime(created_at) DESC LIMIT ?
        """, params: [limit])
        return rows.compactMap { r in
            guard let id = r["id"] as? String,
                  let userId = r["user_id"] as? String,
                  let name = r["name"] as? String,
                  let updatedAt = r["updated_at"] as? String else { return nil }
            return AgentRow(
                id: id, userId: userId, name: name,
                codename: r["codename"] as? String,
                role: r["role"] as? String ?? "analyst",
                status: r["status"] as? String ?? "standby",
                totalFindings: (r["total_findings"] as? Int64).map(Int.init) ?? 0,
                lastScannedAt: r["last_scanned_at"] as? String,
                createdAt: r["created_at"] as? String ?? updatedAt,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Directives

    func upsertDirectives(_ rows: [DirectiveRow]) {
        guard !rows.isEmpty else { return }
        beginTransaction(); defer { commitTransaction() }
        for row in rows {
            exec("""
            INSERT INTO directives (id, user_id, type, title, content, is_active, priority, target, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type       = excluded.type,
                title      = excluded.title,
                content    = excluded.content,
                is_active  = excluded.is_active,
                priority   = excluded.priority,
                target     = excluded.target,
                updated_at = excluded.updated_at
            """, params: [row.id, row.userId, row.type, row.title, row.content, row.isActive ? 1 : 0, row.priority, row.target as Any?, row.updatedAt])
        }
    }

    func fetchDirectives() -> [DirectiveRow] {
        let rows = query("""
        SELECT id, user_id, type, title, content, is_active, priority, target, updated_at
        FROM directives ORDER BY priority DESC, datetime(updated_at) DESC
        """, params: [])
        return rows.compactMap { r in
            guard let id = r["id"] as? String,
                  let userId = r["user_id"] as? String,
                  let title = r["title"] as? String,
                  let content = r["content"] as? String,
                  let updatedAt = r["updated_at"] as? String else { return nil }
            let active = ((r["is_active"] as? Int64).map { $0 != 0 }) ?? true
            return DirectiveRow(
                id: id, userId: userId,
                type: r["type"] as? String ?? "directive",
                title: title, content: content,
                isActive: active,
                priority: (r["priority"] as? Int64).map(Int.init) ?? 0,
                target: r["target"] as? String,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Memories

    func upsertMemories(_ rows: [MemoryRow]) {
        guard !rows.isEmpty else { return }
        beginTransaction(); defer { commitTransaction() }
        for row in rows {
            exec("""
            INSERT INTO memories (id, user_id, type, content, source, is_active, priority, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type       = excluded.type,
                content    = excluded.content,
                source     = excluded.source,
                is_active  = excluded.is_active,
                priority   = excluded.priority,
                updated_at = excluded.updated_at
            """, params: [row.id, row.userId, row.type, row.content, row.source as Any?, row.isActive ? 1 : 0, row.priority, row.updatedAt])
        }
    }

    func fetchMemories(limit: Int = 200) -> [MemoryRow] {
        let rows = query("""
        SELECT id, user_id, type, content, source, is_active, priority, updated_at
        FROM memories WHERE is_active = 1
        ORDER BY priority DESC, datetime(updated_at) DESC
        LIMIT ?
        """, params: [limit])
        return rows.compactMap { r in
            guard let id = r["id"] as? String,
                  let userId = r["user_id"] as? String,
                  let content = r["content"] as? String,
                  let updatedAt = r["updated_at"] as? String else { return nil }
            let active = ((r["is_active"] as? Int64).map { $0 != 0 }) ?? true
            return MemoryRow(
                id: id, userId: userId,
                type: r["type"] as? String ?? "fact",
                content: content,
                source: r["source"] as? String,
                isActive: active,
                priority: (r["priority"] as? Int64).map(Int.init) ?? 5,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Unified search (across cached datasets)

    struct SearchHit: Sendable {
        let kind: String       // "conversation" | "operation" | "record" | "agent" | "memory" | "directive"
        let id: String
        let label: String
        let snippet: String
    }

    /// LIKE-based fuzzy search across the cached tables. Fast because it's
    /// local — no network round-trips per keystroke. Limited to ~12 hits per
    /// kind to keep the result list scannable.
    func search(_ q: String, perKind: Int = 12) -> [SearchHit] {
        let needle = "%\(q.trimmingCharacters(in: .whitespacesAndNewlines))%"
        guard !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var hits: [SearchHit] = []

        for r in query("""
        SELECT id, title, COALESCE(preview, '') AS preview FROM conversations
        WHERE title LIKE ? OR preview LIKE ? ORDER BY datetime(updated_at) DESC LIMIT ?
        """, params: [needle, needle, perKind]) {
            guard let id = r["id"] as? String, let title = r["title"] as? String else { continue }
            hits.append(SearchHit(kind: "conversation", id: id, label: title, snippet: r["preview"] as? String ?? ""))
        }

        for r in query("""
        SELECT id, name, COALESCE(codename, '') AS codename FROM operations
        WHERE name LIKE ? OR codename LIKE ? ORDER BY datetime(updated_at) DESC LIMIT ?
        """, params: [needle, needle, perKind]) {
            guard let id = r["id"] as? String, let name = r["name"] as? String else { continue }
            hits.append(SearchHit(kind: "operation", id: id, label: name, snippet: r["codename"] as? String ?? ""))
        }

        for r in query("""
        SELECT id, title, COALESCE(content, '') AS content FROM operation_records
        WHERE archived_at IS NULL AND (title LIKE ? OR content LIKE ?)
        ORDER BY datetime(updated_at) DESC LIMIT ?
        """, params: [needle, needle, perKind]) {
            guard let id = r["id"] as? String, let title = r["title"] as? String else { continue }
            let snippet = String((r["content"] as? String ?? "").prefix(140))
            hits.append(SearchHit(kind: "record", id: id, label: title, snippet: snippet))
        }

        for r in query("""
        SELECT id, name, COALESCE(role, '') AS role FROM agents
        WHERE name LIKE ? OR codename LIKE ? OR role LIKE ?
        ORDER BY datetime(created_at) DESC LIMIT ?
        """, params: [needle, needle, needle, perKind]) {
            guard let id = r["id"] as? String, let name = r["name"] as? String else { continue }
            hits.append(SearchHit(kind: "agent", id: id, label: name, snippet: r["role"] as? String ?? ""))
        }

        for r in query("""
        SELECT id, content, COALESCE(type, 'fact') AS type FROM memories
        WHERE is_active = 1 AND content LIKE ?
        ORDER BY priority DESC LIMIT ?
        """, params: [needle, perKind]) {
            guard let id = r["id"] as? String, let content = r["content"] as? String else { continue }
            let snippet = String(content.prefix(140))
            hits.append(SearchHit(kind: "memory", id: id, label: snippet, snippet: r["type"] as? String ?? "fact"))
        }

        for r in query("""
        SELECT id, title, content FROM directives
        WHERE is_active = 1 AND (title LIKE ? OR content LIKE ?)
        ORDER BY priority DESC LIMIT ?
        """, params: [needle, needle, perKind]) {
            guard let id = r["id"] as? String, let title = r["title"] as? String else { continue }
            let snippet = String((r["content"] as? String ?? "").prefix(140))
            hits.append(SearchHit(kind: "directive", id: id, label: title, snippet: snippet))
        }

        return hits
    }

    // MARK: - SQLite plumbing

    private func openDatabase() {
        guard let url = LumenLocalDB.fileURL else {
            openErrorMessage = "Could not resolve Application Support directory"
            return
        }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            openErrorMessage = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            return
        }
        db = handle

        // Pragma tuning: WAL gives concurrent read while sync writes; foreign
        // keys keep cascade-deletes honest; busy_timeout avoids spurious
        // SQLITE_BUSY when sync + UI hit the file at the same instant.
        exec("PRAGMA journal_mode = WAL", params: [])
        exec("PRAGMA foreign_keys = ON", params: [])
        exec("PRAGMA busy_timeout = 3000", params: [])

        runMigrations()
    }

    private func runMigrations() {
        let current = currentSchemaVersion()
        let migrations: [(Int, () -> Void)] = [
            (1, migration1_initialSchema),
            (2, migration2_pendingSyncColumn),
        ]
        for (version, migrate) in migrations where version > current {
            migrate()
            exec("PRAGMA user_version = \(version)", params: [])
        }
    }

    /// Adds the `pending_sync` flag to conversations so the sync engine can
    /// retry optimistic-write rows whose initial server-side create failed.
    private func migration2_pendingSyncColumn() {
        exec("ALTER TABLE conversations ADD COLUMN pending_sync INTEGER NOT NULL DEFAULT 0", params: [])
        exec("CREATE INDEX IF NOT EXISTS idx_conversations_pending ON conversations(pending_sync) WHERE pending_sync = 1", params: [])
    }

    private func currentSchemaVersion() -> Int {
        let rows = query("PRAGMA user_version", params: [])
        return (rows.first?.values.first as? Int64).map(Int.init) ?? 0
    }

    private func migration1_initialSchema() {
        let stmts = [
            """
            CREATE TABLE IF NOT EXISTS conversations (
                id            TEXT PRIMARY KEY,
                user_id       TEXT NOT NULL,
                title         TEXT NOT NULL,
                source        TEXT,
                created_at    TEXT,
                updated_at    TEXT NOT NULL,
                preview       TEXT,
                message_count INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC)",

            """
            CREATE TABLE IF NOT EXISTS messages (
                id              TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                role            TEXT NOT NULL,
                content         TEXT NOT NULL,
                created_at      TEXT NOT NULL,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at)",

            """
            CREATE TABLE IF NOT EXISTS operations (
                id          TEXT PRIMARY KEY,
                user_id     TEXT NOT NULL,
                name        TEXT NOT NULL,
                codename    TEXT,
                status      TEXT,
                priority    TEXT,
                description TEXT,
                directives  TEXT,
                created_at  TEXT,
                updated_at  TEXT NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_operations_updated ON operations(updated_at DESC)",

            """
            CREATE TABLE IF NOT EXISTS operation_records (
                id           TEXT PRIMARY KEY,
                operation_id TEXT,
                user_id      TEXT NOT NULL,
                type         TEXT NOT NULL,
                title        TEXT NOT NULL,
                content      TEXT,
                status       TEXT,
                priority     TEXT,
                pinned       INTEGER NOT NULL DEFAULT 0,
                archived_at  TEXT,
                created_at   TEXT NOT NULL,
                updated_at   TEXT NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_records_updated ON operation_records(updated_at DESC)",
            "CREATE INDEX IF NOT EXISTS idx_records_op ON operation_records(operation_id)",

            """
            CREATE TABLE IF NOT EXISTS agents (
                id              TEXT PRIMARY KEY,
                user_id         TEXT NOT NULL,
                name            TEXT NOT NULL,
                codename        TEXT,
                role            TEXT,
                status          TEXT,
                total_findings  INTEGER NOT NULL DEFAULT 0,
                last_scanned_at TEXT,
                created_at      TEXT,
                updated_at      TEXT NOT NULL
            )
            """,

            """
            CREATE TABLE IF NOT EXISTS directives (
                id         TEXT PRIMARY KEY,
                user_id    TEXT NOT NULL,
                type       TEXT NOT NULL,
                title      TEXT NOT NULL,
                content    TEXT NOT NULL,
                is_active  INTEGER NOT NULL DEFAULT 1,
                priority   INTEGER NOT NULL DEFAULT 0,
                target     TEXT,
                updated_at TEXT NOT NULL
            )
            """,

            """
            CREATE TABLE IF NOT EXISTS memories (
                id         TEXT PRIMARY KEY,
                user_id    TEXT NOT NULL,
                type       TEXT NOT NULL,
                content    TEXT NOT NULL,
                source     TEXT,
                is_active  INTEGER NOT NULL DEFAULT 1,
                priority   INTEGER NOT NULL DEFAULT 5,
                updated_at TEXT NOT NULL
            )
            """,

            """
            CREATE TABLE IF NOT EXISTS sync_state (
                table_name           TEXT PRIMARY KEY,
                last_seen_updated_at TEXT,
                last_synced_at       TEXT NOT NULL,
                last_reconciled_at   TEXT
            )
            """,
        ]
        for s in stmts { exec(s, params: []) }
    }

    // MARK: - Generic exec / query

    @discardableResult
    private func exec(_ sql: String, params: [Any?]) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log(sql: sql, prefix: "prepare failed")
            return false
        }
        bind(stmt: stmt, params: params)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            log(sql: sql, prefix: "step rc=\(rc)")
            return false
        }
        return true
    }

    private func query(_ sql: String, params: [Any?]) -> [[String: Any]] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log(sql: sql, prefix: "query prepare failed")
            return []
        }
        bind(stmt: stmt, params: params)

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let colCount = sqlite3_column_count(stmt)
            for i in 0..<colCount {
                let nameC = sqlite3_column_name(stmt, i)
                let name = nameC.map { String(cString: $0) } ?? "col\(i)"
                row[name] = columnValue(stmt: stmt, index: i)
            }
            results.append(row)
        }
        return results
    }

    private func columnValue(stmt: OpaquePointer?, index: Int32) -> Any {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER: return sqlite3_column_int64(stmt, index)
        case SQLITE_FLOAT:   return sqlite3_column_double(stmt, index)
        case SQLITE_TEXT:
            return sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
        case SQLITE_BLOB:
            let bytes = sqlite3_column_bytes(stmt, index)
            if bytes <= 0 { return Data() }
            return Data(bytes: sqlite3_column_blob(stmt, index), count: Int(bytes))
        default: return NSNull()
        }
    }

    private func bind(stmt: OpaquePointer?, params: [Any?]) {
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case nil, is NSNull:
                sqlite3_bind_null(stmt, idx)
            case let v as String:
                sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case let v as Bool:
                sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as Data:
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            default:
                // Fall back to string description so we never crash on an
                // unexpected type — better to log a malformed value than to
                // throw and lose the whole sync.
                sqlite3_bind_text(stmt, idx, String(describing: value), -1, SQLITE_TRANSIENT)
            }
        }
    }

    private func beginTransaction() { exec("BEGIN", params: []) }
    private func commitTransaction() { exec("COMMIT", params: []) }

    private func log(sql: String, prefix: String) {
        guard let db else { return }
        let msg = String(cString: sqlite3_errmsg(db))
        print("[lumen-db] \(prefix): \(msg) — sql=\(sql.prefix(140))")
    }
}

// Shared ISO8601 formatter for sync timestamps. Keep separate from any
// per-call formatter so we don't pay the allocation tax on hot paths.
private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
