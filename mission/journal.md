# Mission Journal

Append-only log of significant changes, decisions, and incidents.

---

## 2026-05-03 — Cleanup pass

**Context:** First evaluation by Claude Code session. Project had been built for ~6 weeks with only 2 commits (`first version`, `Initial folder structure`). Lots of structural drift.

**Discovered:**
- 57 modified files, 17+ untracked.
- 2 empty brace-expansion folders (`{nexus-web,docs,shared,scripts}/` and `{nexus-web,nexus-ios,arena/`) — leftover from a misquoted `mkdir`.
- `SESSION-LOG.md` had ~220 lines of identical content because the Stop hook ran `git log --oneline -5` after every session, and the only commits never changed.
- `lumen/lumen-desktop/lumen-desktop/LumenAPIManager.swift:72` had `"PASTE_YOUR_KEY_HERE"` placeholder — false alarm in PROJECT-STATUS.md, but real future risk.
- Vercel watches `o-nexus`, not `nexus` — prod stale.

**Done in this session:**
- Removed both empty brace-expansion folders.
- Created `mission/` folder for ongoing operational state (this folder).
- Truncated `SESSION-LOG.md` (gitignored, no data loss).
- Wrote pending API-key refactor to `mission/pending-changes.md` (deferred — Xcode active on those files).
- Planned commit groupings (see below).

**Commit grouping plan:**

| Group | Files | Commit message |
|---|---|---|
| A | `.gitignore` + .obsidian/* untracked from gitignore | `chore: gitignore obsidian workspace state and tighten patterns` |
| B | `nexus-web/app/api/**` + `nexus-web/proxy.ts` + `nexus-web/app/auth/**` + `nexus-web/app/dashboard/**` | `nexus-web: Bearer auth, agents pipeline, groups, security flows` |
| C | All of `desktop/` (untracked) | `desktop: Electron + Vite + React HUD app for nexus services` |
| D | `lumen/lumen-desktop/**` Swift changes | `lumen: 3-tier brain fallback, Bearer auth, conversation threading` (held — Xcode active) |
| E | `memory/` canvases + workspace | `memory: vault canvases and obsidian workspace` |
| F | `.claude/`, `mission/`, `PROJECT-STATUS.md` | `chore: mission memory + claude config + status doc` |

Group D is held until Xcode debug session ends to avoid staging mid-edit content.

**Result — 5 commits landed:**
- `52a7ffe` chore: gitignore obsidian workspace state and untrack tracked
- `fb2cf90` nexus-web: Bearer auth, agents pipeline, groups, security flows (38 files)
- `591f138` desktop: Electron + Vite + React HUD app (32 files)
- `c4c911e` memory: vault canvases and daily note (5 files)
- `9dc300c` chore: mission memory + claude config + status doc (8 files)

Total: 88 files committed. Repository went from 2 commits to 7.

**Held intentionally (live edits in progress during cleanup):**
- Lumen Swift (Xcode debug session active).
- nexus-ios changes (something else editing).
- arena/ + new nexus-web/lib/arena, lib/eve, ArenaActivityWidget, DashboardHome modifications, migration 017 (appeared during session — likely cursor/codex editing live).

**Not done (queued):**
- Push to remote: `git push origin main`. Holding until Patrick confirms — Vercel watches the wrong repo, so push timing matters.
- Vercel reconnect (Patrick, manual).
- QStash keys (Patrick, manual).
- API-key refactor (Xcode active — see pending-changes.md).
- Commit the held lumen/ios/arena changes when their editors are at a checkpoint.

---

## 2026-05-06 — Arena pivot + standalone platform build

**Context:** Patrick course-corrected away from NOADS: *"Not sure noads is critical when we have arena and so many unfinished parts of nexus."* Then framed Arena as needing its own web platform: *"Arena is going to need its own web app to connect to so users can go there and connect their nexus account to arena then they should be able to connect and add more connections inside of lumen."*

**Done:**
- Built `arena-web` as a standalone Next.js 16 app at `/code/nexus/arena-web/`. Separate Vercel project (`arena-web`).
- 5 provider integrations (ClickUp, Notion, GitHub, Stripe, Slack) with a clean `Provider` interface — adding a new provider = one file in `lib/providers/`.
- Connection management UI: list, add, edit, rotate credentials, test, delete.
- Auto health tracking via `lib/connection-health.ts` — auth errors flip status to errored.
- Eve tool routing: 3 task/payment tools accept optional `provider` param. New `arena_providers` and `arena_failures` tools for Eve self-introspection.
- First-run guide for users with zero connections + zero actions.
- Connection-error notification email via Resend (24h throttle, migration 022).
- Cross-subdomain cookie auth via `SESSION_COOKIE_DOMAIN` env var (set by Patrick when DNS lands).

Old `arena/` Express service is now superseded. `arena-launch.md` is stale; current state is in `arena-platform.md`.

---

## 2026-05-07 — Webhook receiver + nexus-web polish + face-api fix

### Arena webhook receiver foundation

- New route `arena-web/app/api/webhooks/[connectionId]/[secret]/route.ts`
- Per-connection `webhook_secret` column auto-generated on insert (migration 023, default `encode(gen_random_bytes(24), 'hex')`)
- URL displayed in connection edit form with Copy button — paste into provider's webhook settings
- Inbound events logged to `arena_action_log` with action prefix `inbound/{provider}/{event}` and caller='system'
- Slack URL-verification challenge handled
- Per-provider HMAC signature verification deferred (path-token gating is MVP)

### nexus-web mobile + broken-parts pass

Triggered by Patrick: *"Lots of broken parts and mobile issues."* Then more specifically: *"chat ui is really broken it is all bunched up not taking up fullwidth."*

Sweep covered Maxwell chat (touch targets, error handling, mobile width), Settings/Console mobile, Suits/Systems honesty banners, agents/humans page mobile fixes, EveMessage failure styling. Full inventory in `mission/nexus-web-polish-2026-05.md`.

### Suits page wired to real agents

Replaced the hardcoded Tony Stark suits array with real `agents` table queries. Same HUD aesthetic, real data. Empty state CTAs to `/dashboard/agents`.

### Lumen face login server-side fix (CRITICAL)

Lumen native face capture was getting back opaque "SERVER ERROR" with no detail. Root cause: `@vladmandic/face-api`'s package.json `main` field points at `face-api.node.js` which hard-requires `@tensorflow/tfjs-node` (30MB native binary, blows Vercel's 250MB cap, AND pnpm strict isolation hides it from face-api).

Fix: imported `@vladmandic/face-api/dist/face-api.node-wasm.js` directly, added `@tensorflow/tfjs-backend-wasm`. WASM gives ~150-300ms inference, no native binaries. Memory at `/Users/shadow/.claude/projects/-Users-shadow-code/memory/feedback_vercel_native_deps.md` updated with the exact incantation.

Also wrapped both `loadFaceApi()` and inference in try/catch with detail in JSON response so future failures are diagnosable from Lumen's UI.

**Test verified:** sample image returns `FACE_MISMATCH` (correct — it's not Patrick) instead of opaque 500.
