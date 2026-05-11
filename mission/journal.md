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

---

## 2026-05-07 (evening) — Operation Calendar (native scheduling)

Built a native scheduling system in nexus-web. Schema: `schedules` + `schedule_runs` tables (migration 024). Vercel Cron hits `/api/schedules/runner` every minute, locks due rows via optimistic update, dispatches by `target_type` (eve_chat / agent_run / operation_brief / arena_action), writes audit row.

UI: `/dashboard/calendar` with cron preset chips, live next-3-firings preview in the modal, expandable history, **Run Now button** for skipping the cron tick during testing. Eve gets `schedule_create` + `schedule_list` tools.

External calendar sync (Google / Apple) deferred to land later as Arena providers.

---

## 2026-05-07 (late evening) — Domains live + cross-subdomain cookie fix

Patrick set up DNS for `maxnexus.io`, `portal.maxnexus.io`, `arena.maxnexus.io`. Hit a snag: signing in to portal didn't carry to arena. Root cause: `SESSION_COOKIE_DOMAIN` env var was never actually set on Vercel (despite mission docs claiming it was). Fixed via `vercel env add SESSION_COOKIE_DOMAIN=.maxnexus.io` on both projects + redeploy.

Cookie chain verified end-to-end via curl with a real session row from Supabase. Both domains accept the same `nx_session` cookie.

---

## 2026-05-07 (evening) — Splash page (maxnexus-public)

Standalone Next.js app at `/code/nexus/maxnexus-public/`. Public face for `maxnexus.io`. Ambient particle field + Dagaz rune doorway. Click rune → "What is light?" → answer "lumen" (with 1-character typo tolerance) → redirect to portal. Wrong answer → candle screen with "Find a candle and light it." Easter eggs for `vera`, `eve`, `noads`. Search engines blocked via `robots: { index: false, follow: false }`.

Folder originally created as `splash-web`, renamed to `maxnexus-public` per Patrick's request — better identity-tied name, room to grow into real marketing surface later.

---

## 2026-05-07 (late evening) — ClickUp OAuth (1st multi-user provider)

Patrick rejected the manual API key UX: "i want it to ping clickup, register the connection, then bring me back to arena to make settings and rules." Built OAuth flow:
- `lib/oauth/clickup.ts` — helpers (state minting + verification, authorize URL builder, token exchange, fetch user/teams)
- `/api/oauth/clickup/start` — sets signed state cookie, redirects to ClickUp consent
- `/api/oauth/clickup/callback` — exchanges code → token → persists connection → redirects to settings page
- `/api/oauth/clickup/lists` — live list picker data for settings page
- `/connect/clickup` — Apple-styled landing with **inline 6-step admin setup guide** (no doc-hunting required)
- `/connect/clickup/[id]/settings` — workspace picker + default list dropdown (live from ClickUp) + Eve permission toggles + webhook URL + disconnect
- `/connect/clickup/manual` — legacy fallback for personal API tokens

Critical bug fixes:
1. ClickUp OAuth tokens require `Authorization: Bearer <token>` (not bare `<token>` like personal tokens). Added `clickupAuthHeader()` helper.
2. Token exchange was using URL query params; switched to form-encoded body per docs.
3. Eve handoff: Arena's `/api/task/create` now returns `{ needs_connection, connect_url, message }` when no connection exists, instead of silently mocking. Eve's system prompt has a directive to surface the connect URL naturally.

---

## 2026-05-08 (overnight 02:00-02:45) — Major design overhaul + 3 more OAuth providers + detail routes

Patrick's mandate: "I wanna see your masterpiece without influence from me." This was the big push.

### Theme lockdown
- `useTheme.ts` locked to `colorMode: dark, uiMode: simple`. Theme toggle button hidden from sidebar. Light mode + futuristic-mode CSS blocks remain in globals.css but never trigger.

### Design system primitives
- New `components/ui/primitives.tsx` with `Card` (5 padding × 5 tone), `Button` (5 variants × 3 sizes + loading state), `Input`, `Pill` (6 tones × 2 sizes), `Section`, `EmptyState`, `StatTile`, `Skeleton`, `Tabs`.
- New `components/ui/UserAvatar.tsx` with deterministic colored-initials fallback. Wired into sidebar / Maxwell chat / Settings / Humans list.
- Globals refined: 3-tier dark surface hierarchy (oklch L 0.135 / 0.165 / 0.21), hairline borders (alpha 0.08), single deep-blue accent (oklch 0.70 0.16 248), Apple-style optical typography (-0.011em body tracking, -0.018em headings), tabular numerals.

### Full HUD chrome scrub
Zero remaining cyan/HUD/`tracking-widest` classes in: MaxwellClient, EveMessage, EveCommand, SettingsClient, ConsoleClient, CalendarClient, Operations page, Agents page, Humans page, ArenaPanel, EndpointsHealth, all 7 home widgets, Auth pages (PIN/face/error), Arena dashboard + ConnectionsList + RecentActions + FirstRunGuide.

Map page + Suits page kept HUD by intent.

### DashboardHome rebuild
4-tile stats row (Active ops / Records / Agents / Memories), all 6 home widgets unified on `bg-card border-border rounded-xl` surface (dropped per-widget tinted backgrounds — violet, amber, emerald, primary).

### Per-entity detail routes — direct response to "drill down deeper"
- `/dashboard/humans/[id]` — Profile / Sessions / Activity tabs + admin actions panel (Lock / Reset PIN). Linked from humans list rows.
- `/dashboard/agents/[id]` — Profile / Findings tabs + Run Now button. Linked from agents grid cards.
- `/dashboard/operations/[id]` — Overview / Records / Briefs tabs. Linked from operations master-detail header ("Full view ↗").

### 3 more OAuth providers (Notion, GitHub, Slack)
Each with same shape as ClickUp: helper lib, start/callback/{data} routes, Apple-styled connect landing with inline admin setup guide, per-connection settings page with live data picker (databases / repos / channels), provider lib updated to read `access_token` first / fall back to legacy.

**4 of 5 providers now have OAuth.** Stripe stays manual (intentional — payments are high-blast-radius and shouldn't be casually wired).

### Eve handoff for missing connections
Arena's `/api/task/create` now returns `{ success: false, needs_connection: true, provider, provider_name, connect_url, message }` when the user has no matching connection. Eve's system prompt has a new directive: "If an arena tool returns needs_connection: true, the user hasn't connected that service yet. Surface this naturally: tell them which service needs connecting and give them the connect_url from the response as a clickable link."

### Mission docs cleanup
talkcircles.io references swept to maxnexus.io across state.md / handoff.md / pending-changes.md / arena-platform.md.
