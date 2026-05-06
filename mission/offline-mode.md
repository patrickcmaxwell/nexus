# Offline Mode

**Created:** 2026-05-04
**Sequencing:** After Operation Letsgo (`operation-letsgo.md`), before Arena launch (`arena-launch.md`). Arena writes through nexus-web; the outbox needs to exist before Arena goes prod.
**Goal:** Nexus stays usable when the laptop has no internet. Eve answers via Ollama. Lumen opens via local-cached credentials. Writes queue locally and sync to Supabase on reconnect. The Director can travel without losing the system.

---

## Why this is its own op

Operation Letsgo is plumbing — boot, restart, pause. The offline-mode work is **architecture**:
- Auth flow needs to fall back to a local credential store.
- nexus-web's "Supabase is the only source of truth" assumption needs to be relaxed.
- Lumen + iOS need network-state awareness so they don't hang on dead remote endpoints.
- Tool calls (Arena, Tavily, ClickUp) need to refuse politely when offline, not stack-trace.

Rolling this into Letsgo would balloon it from a 2-day plumbing op to a 2-week architecture op. Keep them separate.

---

## Current offline reality

| Component | Offline state today | Why |
|---|---|---|
| Ollama (local LLM) | ✅ works | local |
| Lumen UI shell | ✅ works | native |
| `llava:7b` vision | ✅ works | local Ollama |
| System TTS (`AVSpeechSynthesizer`) | ✅ works | offline fallback exists |
| nexus-web server itself | ⚠️ starts, most routes fail | Supabase + Grok calls 401/timeout |
| Eve via `/api/eve` | ❌ fails | Grok cloud |
| Eve via `/api/eve/local` | ⚠️ partial | Ollama works, but Supabase memory/threading dies |
| Supabase reads/writes | ❌ fails | cloud Postgres |
| ElevenLabs TTS | ❌ fails | cloud |
| Tavily web search | ❌ fails | cloud |
| Claude API fallback | ❌ fails | cloud, hard-fails |
| **PIN + face auth** | ❌ **fails** | every auth round-trips Supabase |

The "local LLM mode" handles brain. It doesn't handle auth, memory persistence, threading, or tool calls.

---

## Layer 1 — Local credential cache (unblocks "Lumen opens offline")

This is the smallest discrete win. Lumen can open without internet if it has a local copy of the auth material.

### L1.1 — Credential storage location
**Path:** `~/Library/Application Support/Lumen/credentials/`

**Contents (encrypted via macOS Keychain wrapping):**
- `pin.hash` — bcrypt hash of last successful PIN
- `face.descriptor` — JSON copy of `humans.face_descriptor` (the same thing currently in Supabase)
- `session.token` — last issued session id, with `expires_at`
- `last_online.iso` — timestamp of last successful Supabase round-trip
- `human_id.txt` — UUID of the authenticated human (for offline writes that need an author)

**Director-managed:** Yes. The Director can `rm -rf` the credentials dir to force re-auth, or `vera auth clear` to do it cleanly.

**Acceptance:** Files exist after first online auth, are unreadable without Keychain unlock.

**Estimate:** 2h.

### L1.2 — `LumenAuth` fallback path
**File:** `lumen/lumen-desktop/lumen-desktop/LumenAuth.swift` (and friends)

**Approach:**
- On auth attempt, try `/api/security/enter` with 5s timeout.
- On network failure (not on credential rejection — those still fail), fall back to local cache:
  - PIN: bcrypt-compare against `pin.hash`.
  - Face: compare descriptor distance against `face.descriptor` with the same threshold the server uses.
- TTL: PIN cache valid 30 days from `last_online.iso`. Face descriptor valid indefinitely (re-enroll forces refresh).
- On successful local auth, surface "OFFLINE MODE" pill in Lumen TopHUD so the Director knows they're in degraded auth.

**Acceptance:**
- Pull ethernet → relaunch Lumen → PIN works → enter → "OFFLINE MODE" pill visible.
- Plug ethernet back in → next auth tries Supabase first and clears the pill.

**Estimate:** half day.

### L1.3 — Sync on reconnect
**Approach:**
- When network returns (detected by `NWPathMonitor`, see Layer 3), Lumen pushes any local-only sessions to `security_sessions` and refreshes `face.descriptor` from `humans`.
- Conflict resolution: server wins on face descriptor (admin re-enroll takes precedence); local wins on session timestamps.

**Acceptance:** Offline session shows up in `security_sessions` after reconnect.

**Estimate:** 2h.

### L1.4 — `vera auth` subcommand
**File:** `nexus/scripts/vera`

**Subcommands:**
- `vera auth status` — last online timestamp, cache TTL remaining, mode (online/offline)
- `vera auth clear` — wipes credentials dir, forces next auth to be online-only
- `vera auth refresh` — force-pulls latest face descriptor + session from Supabase

**Acceptance:** Director can inspect/manage credential state from CLI.

**Estimate:** 1h.

### Layer 1 first-boot constraint
**Must be online once before offline auth works.** Document in Lumen's first-launch screen and `vera install` output. There's no way around this — credential material has to come from somewhere.

---

## Layer 2 — Outbox + read-through cache (unblocks "writes survive offline")

This is the real engineering work. Without it, Eve can chat offline (via Ollama) but can't update memory, log conversations, run agents, or fire Arena tools that depend on Supabase persistence.

### L2.1 — Local SQLite outbox
**File:** `nexus-web/.cache/outbox.db` (gitignored)

**Schema:**
```sql
create table outbox (
  id            text primary key,            -- ulid
  table_name    text not null,               -- 'eve_history', 'operation_records', etc.
  op            text not null,               -- 'insert' | 'update' | 'delete'
  row           text not null,               -- JSON of the row payload
  status        text not null default 'pending', -- 'pending' | 'synced' | 'conflict'
  created_at    text not null,
  synced_at     text,
  error_msg     text
);
create index on outbox (status, created_at);

create table cache (
  table_name    text not null,
  pk            text not null,
  row           text not null,               -- JSON
  fetched_at    text not null,
  primary key (table_name, pk)
);
```

**Acceptance:** SQLite file is created on nexus-web startup; schema migrations idempotent.

**Estimate:** 2h.

### L2.2 — Write-through pattern in nexus-web Supabase calls
**Files:** `nexus-web/lib/supabase/*.ts`, `nexus-web/lib/eve/*.ts`, anywhere Supabase is written

**Approach:**
- Wrap Supabase writes in a `writeWithOutbox(table, op, row)` helper.
- The helper:
  1. Inserts into `outbox` first (always succeeds — local).
  2. Attempts the Supabase write with 5s timeout.
  3. On success, marks outbox row `synced`.
  4. On failure (timeout, network, 5xx), leaves it `pending`.
- Caller gets a synthetic success response so the user-facing flow doesn't degrade.
- Reads use a `readWithCache(table, pk)`: try Supabase first (5s), fall back to `cache` table on failure.

**Acceptance:** Pull ethernet → send Eve message → message appears in conversation locally → reconnect → message lands in Supabase.

**Estimate:** 2 days. This is the real work — every Supabase call needs to go through the helper, and the helper needs to handle every failure mode without corrupting state.

### L2.3 — Sync worker
**File:** `nexus-web/lib/supabase/sync-worker.ts`

**Approach:**
- Background job (interval timer in nexus-web process) that drains `outbox where status='pending'` to Supabase.
- On success → mark `synced`.
- On 4xx (validation/conflict) → mark `conflict`, log to `journal.md` for Director review.
- On 5xx/timeout → leave `pending`, retry next tick.
- Conflict resolution: last-write-wins keyed by `updated_at`. Good enough for single-user. CRDT only when multi-device gets serious (defer).

**Acceptance:** After 1h offline + 100 writes, reconnect → all 100 land in Supabase within 60s.

**Estimate:** 1 day.

### L2.4 — Backfill cache on online reads
**Approach:** Every successful read from Supabase upserts into the local `cache` table. Cache is read-through, write-on-read.

**Acceptance:** After a normal online session, cache contains all rows the Director touched. Going offline immediately after = full read fidelity for that session's data.

**Estimate:** 4h.

### L2.5 — `vera sync` subcommand
**File:** `nexus/scripts/vera`

**Subcommands:**
- `vera sync status` — count of pending/synced/conflict rows in outbox
- `vera sync now` — force a drain pass (useful right after reconnect, before timer fires)
- `vera sync conflicts` — list rows in conflict state with diffs

**Acceptance:** Director can see and manage sync state from CLI.

**Estimate:** 2h.

---

## Layer 3 — Network-aware brain routing (unblocks "Eve degrades gracefully")

### L3.1 — `NWPathMonitor` in Lumen + iOS
**Files:** `lumen/lumen-desktop/lumen-desktop/NetworkMonitor.swift` (new), iOS equivalent

**Approach:**
- Singleton observable that publishes `.online` / `.offline` / `.constrained` (cellular).
- TopHUD shows OFFLINE pill (amber) when offline; CONSTRAINED pill (yellow) on cellular.
- `LumenStore.send()` reads network state and skips the nexus-web tier when offline, going straight to Ollama.

**Acceptance:** Pull ethernet → OFFLINE pill within 2s. Plug back in → pill clears.

**Estimate:** 3h (Lumen) + 3h (iOS).

### L3.2 — Tool-call refusal when offline
**File:** `nexus-web/app/api/eve/route.ts` system prompt + tool-call guard

**Approach:**
- Before firing any tool that requires internet (`arena_*`, web search, etc.), check network reachability.
- Offline → tool call short-circuits with "I'd run that, but we're offline. Want me to queue it for when we reconnect?" — and queues to a local `pending_tools` table.
- DIRECTIVE in system prompt: "When the result of a tool call is `OFFLINE_DEFERRED`, acknowledge and do not retry until network returns."

**Acceptance:** Offline + ask Eve to create a ClickUp task → polite refusal + queue → reconnect → Eve says "I queued a task earlier; firing now" and runs it.

**Estimate:** 1 day.

### L3.3 — `currentDate` injection
**File:** `nexus-web/app/api/eve/route.ts`

**Quick fix (out of scope but tracked here):** Inject `currentDate: <ISO>` into every Eve system prompt at request time. Eve sometimes confidently says wrong dates already; offline makes it worse. One line of code; high leverage.

**Acceptance:** Ask "what's today's date?" offline → Eve answers correctly.

**Estimate:** 15 min.

---

## Suggested execution order

```
Op 1 — Layer 1: Lumen opens offline (~1.5 days)
  ├─ L1.1: credentials dir + Keychain wrap
  ├─ L1.2: LumenAuth fallback
  ├─ L1.3: sync on reconnect
  └─ L1.4: vera auth subcommand
        → Lumen opens with no internet.

Op 2 — Layer 3: Network awareness (~1.5 days)
  ├─ L3.1: NWPathMonitor + UI pills
  ├─ L3.2: Tool-call refusal + queue
  └─ L3.3: currentDate injection
        → Eve degrades gracefully and stops claiming today is 2024.

Op 3 — Layer 2: Outbox + sync (~4 days, the real engineering)
  ├─ L2.1: SQLite outbox schema
  ├─ L2.2: write-through helpers across nexus-web
  ├─ L2.3: sync worker
  ├─ L2.4: read cache backfill
  └─ L2.5: vera sync subcommand
        → Writes survive offline, sync on reconnect.
```

**Total: ~7 days of focused work.** Layer 1 alone is a meaningful unlock and can ship independently if Layer 2 gets deferred. Layer 2 is the heavy lift; do not start it without dedicated focus.

---

## Risks

- **Outbox + Supabase divergence** — If a row gets edited both offline (in outbox) and online (by another device or a cron job), conflict resolution is non-trivial. Last-write-wins is a defensible default but expect occasional manual cleanup. `vera sync conflicts` exists for this.
- **Encrypted credentials lost** — If macOS Keychain entry is wiped (system reinstall, profile reset), local credential cache becomes unreadable. User has to re-auth online. Acceptable failure mode.
- **Outbox grows unbounded** — A 2-week trip with no internet could pile up thousands of rows. Add `vera sync status` warning at >10k pending. Real fix: schedule auto-truncation of synced rows older than 30 days.
- **Schema migrations during offline period** — If nexus-web schema changes (new column on `eve_history`, etc.) while outbox has pending rows for the old schema, sync may fail. Mitigation: outbox rows are `jsonb`, so adding columns is fine; renames/drops require manual reconciliation.
- **Time skew between local writes and server** — All `created_at` values come from the local clock. If clock is drifted, ordering breaks. `vera doctor` already checks clock drift (Operation Letsgo); reuse the same check.
- **Lumen + iOS divergence** — Both can write to outbox-equivalents on the same human's account. Without CRDT, last-write-wins means an offline iOS edit could clobber an offline Lumen edit. Single-device usage avoids this. Document as known limit; build CRDT only when it bites.

---

## Open questions

- [ ] Should the outbox/cache live inside `nexus-web/.cache/` (process-local) or `~/Library/Application Support/Nexus/` (shared across surfaces)? Default rec: nexus-web local, since only nexus-web reads/writes Supabase. Surfaces talk to nexus-web, not Supabase directly.
- [ ] Should `vera doctor` check outbox health (pending count, oldest pending row age)? Default rec: yes, once Layer 2 lands.
- [ ] Conflict policy for `face_descriptor` re-enroll: server wins always, or local-newer-wins? Default rec: server wins (admin action takes precedence).
- [ ] iOS Layer 1 — separate ticket or part of this op? Default rec: separate ticket; iOS Keychain pattern differs enough to warrant its own pass.

---

## Won't-do

- **CRDT-based merge** — Overkill for current scale. Last-write-wins until multi-device conflicts actually bite.
- **Local-only mode that never syncs** — Confusing UX; would diverge memory between surfaces. Always sync when possible.
- **Mirror full Supabase locally (Postgres-on-Mac)** — Massive overkill. SQLite outbox + cache is sufficient.
- **Encrypted outbox** — The data is already on this machine in plaintext form (Lumen cache, Obsidian vault). No new threat model. Don't waste cycles encrypting SQLite.

---

## Status

### Layer 1
- [ ] **L1.1** — Credentials dir + Keychain wrap
- [ ] **L1.2** — `LumenAuth` fallback path
- [ ] **L1.3** — Sync on reconnect
- [ ] **L1.4** — `vera auth` subcommand

### Layer 2
- [ ] **L2.1** — SQLite outbox schema
- [ ] **L2.2** — Write-through helpers
- [ ] **L2.3** — Sync worker
- [ ] **L2.4** — Read cache backfill
- [ ] **L2.5** — `vera sync` subcommand

### Layer 3
- [ ] **L3.1** — `NWPathMonitor` (Lumen + iOS)
- [ ] **L3.2** — Tool-call refusal + queue
- [ ] **L3.3** — `currentDate` injection

Update this file as items land. Cross-link incidents to `journal.md`.
