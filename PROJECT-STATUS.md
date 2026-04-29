# Nexus Project Status

**Last Updated:** April 28, 2026 — 4:30 PM PST

---

## ✅ Currently Works

### Web App (`nexus-web/`)
- **Supabase Integration**: Connected with `agents`, `agent_activity`, `operations`, `operation_records`, `eve_conversations`, `eve_history`, `eve_memory`, `eve_directives`, `security_sessions`, `humans`, `groups`, `group_members`, and `data_permissions` tables.
- **Autonomous Agent Engine**: `/api/agents/run` feeds conversation histories into `grok-3-mini` in batches of 10, extracts findings, and writes them to `operations` / `operation_records`. Fully functional locally.
- **QStash Agent Pipeline**: `/api/agents/process` added — chained batch processor with QStash signature verification. In prod, `/api/agents/run` publishes to QStash and returns immediately (bypasses Vercel 60s timeout). Locally, runs synchronously as before. Requires Upstash keys in `.env.local`.
- **Eve Auto-Trigger**: Eve's chat tool automatically triggers a background agent scan when an agent's status is set to `ACTIVE`.
- **Project JARVIS UI**: Agents dashboard rebuilt as a sci-fi HUD — holographic core avatars, scanner animations, chamfered clip-path cards, live telemetry stream.
- **Manual Overrides**: `Trigger Scan`, `Force Full Backscan`, and `Pause` buttons linked to Supabase.
- **Eve Web Chat**: Full agentic loop with tool calling (create agents, operations, records, nexus map nodes). Conversation history persisted to Supabase. Background memory summarization every 20 messages.
- **Humans Multi-Tenant System**: Full `humans` table with roles (`observer`, `collaborator`, `operator`, `admin`), invite links, face-recognition seed photos, and inline role editing from the dashboard.
- **Groups Ecosystem**: Create, join, leave, and manage groups. Group owners can edit name/description, view member lists, kick members, and delete groups via a management modal.
- **Granular Visibility Controls**: Agents and Operations can be created with `private`, `shared`, `group`, or `public` visibility. Access enforced via `data_permissions` table and Row Level Security policies.
- **RLS Enforcement**: `012_permissions_rls.sql` migration applied — database-level isolation for operations, agents, and data_permissions based on visibility and group membership.

### Lumen Desktop (`lumen/lumen-desktop/`)
- **SwiftUI native macOS app** — no Electron, no web views.
- **Auth Gate**: PIN (4-digit) + Face scan via nexus-web. Required on first open.
- **LM Studio brain**: All chat goes directly to `localhost:1234` — never through nexus-web. System prompt loaded from Supabase `eve_memory` at startup.
- **Direct Supabase persistence**: New `SupabaseClient.swift` sends messages directly to Supabase REST API (`eve_history`, `eve_conversations`) after every exchange. No nexus-web proxy needed for chat.
- **Conversation threading**: Every session auto-creates a conversation in Supabase on first message, titles it from the opening line, threads all subsequent messages to the same ID.
- **Local session cache**: Current session backed up to `~/Library/Application Support/Lumen/session_cache.json` after every exchange. Loaded on startup if Supabase is unreachable.
- **Conversation sidebar (CHATS panel)**: Loads past conversations directly from Supabase. Tap to view full history.
- **NEW button**: Starts a fresh conversation thread without resetting the session.
- **Agents panel**: Shows real role, last scan time, and total findings from Supabase.
- **Operations panel**: Shows live ops from nexus-web dashboard API.
- **Voice**: SFSpeechRecognizer STT + AVSpeechSynthesizer TTS. Fluid listening mode (auto-restart after Eve speaks).

### iOS App (`nexus-ios/`)
- Supabase + ElevenLabs TTS + voice management. Current integration status TBD.

---

## 🔥 Working On Now

Nothing active. Pick from Next Priorities.

---

## 📌 Next Priorities

1. **QStash Prod Keys** — Add `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `NEXT_PUBLIC_APP_URL` to `.env.local` (and Vercel env vars) from console.upstash.com.
2. **Autonomous Scheduling** — Cron jobs for active agents every 6/12/24h without manual intervention.
3. **Operations Alerts** — Real-time UI toast/badge when agents surface new intel via Supabase Realtime.
4. **Lumen — Conversation Title Update** — After a few exchanges, ask LM Studio to generate a better title and PATCH it in Supabase.
5. **Lumen — Memory Loading** — Load `eve-base.md` and `eve-private.md` from local files to enrich system prompt (offline-first per README).
6. **Nexus Map — Human Nodes** — Show humans on the map with public/shared data profiles and group affiliations.
7. **Group Chat** — Enable group-scoped conversations between humans within the same group.

---

## 🗄️ Database Migrations Applied

| Migration | Description | Status |
|-----------|-------------|--------|
| `001_humans.sql` | `humans`, `groups`, `group_members`, `data_permissions` tables + RLS | ✅ Applied |
| `012_permissions_rls.sql` | Granular RLS policies for operations, agents, data_permissions | ✅ Applied |

---

## 🏗️ Architecture

| Component | Port | Stack |
|-----------|------|-------|
| **nexus-web** | `localhost:3000` | Next.js 16 + Turbopack + Supabase |
| **lumen** (macOS) | N/A | SwiftUI + LM Studio + Supabase direct |
| **Supabase** | Cloud | PostgreSQL + RLS + Service Role API |

---

## 🔐 Security Audit — April 28, 2026

Pre-commit security sweep completed before first GitHub push.

### Fixed
- **Hardcoded service role key** in `lumen/lumen-desktop/lumen-desktop/SupabaseClient.swift` — replaced with placeholder comments. Fill in locally from Supabase Dashboard → Project Settings → API. **Never commit real values.**
- **Xcode `xcuserstate` binary** removed from staging — added `xcuserdata/` and `*.xcuserstate` to root `.gitignore`.
- **Root `.gitignore` hardened** — global `.env*` exclusion added as a backstop for any subdirectory without its own gitignore.

### Confirmed Safe (not a leak)
- `nexus-web/.env.local` — excluded by `nexus-web/.gitignore`, never staged.
- `arena/.env` — excluded by `arena/.gitignore`, never staged.
- `nexus-ios/SupabaseManager.swift` — contains only placeholder values (`YOUR_PROJECT_URL`, `YOUR_ANON_KEY_HERE`).
- All other staged Swift/TS files — no real credentials found.

### Ongoing: Local-Only Secrets
`SupabaseClient.swift` must be filled in locally by each developer. Real credentials live only on your machine and in the Supabase dashboard. Do not store them in any committed file.

---

## 🚧 Blockers / Known Issues

- QStash prod keys not yet added — agent scans still timeout in Vercel prod until those are filled in.
- Lumen desktop: LM Studio must be running at `localhost:1234` for Eve to respond. If it's down, app shows a clear error message.
- Lumen `SourceKit` shows cross-file "cannot find type" warnings in the IDE — these are single-file analysis artifacts and all resolve at Xcode build time.

---

*Update this file every time you sit down to work.*
