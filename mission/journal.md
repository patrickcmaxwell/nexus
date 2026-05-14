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

---

## 2026-05-09 → 2026-05-12 — Multi-day session (Lumen + Nexus iOS heavy buildout)

**Context:** Long /remote-control session driven by Patrick. iOS app went from "barebones" to feature-complete-on-Phase-1. Lumen got security hardening, full chat-UX rebuild, terminal bridge actually working end-to-end, and a long chase on the "Camera silently denied" issue ending with the right fix in pbxproj signing.

### Cross-device terminal bridge — Phase 2 complete + end-to-end working

- Eve tools `terminal_list` / `terminal_send` / `terminal_close` added to `nexus-web/app/api/eve/route.ts` (~110 lines). Direct supabase access; stale-promotion mirrors the GET route; fuzzy session_match by title/folder.
- **2026-05-12 — URL mismatch fix**: Lumen's `LumenAPIManager.remoteBase` was hardcoded to legacy `https://nexus.talkcircles.io`; iOS was hardcoded to `https://portal.maxnexus.io`. Different DBs, bridge silently never connected. Migrated Lumen to `portal.maxnexus.io`.
- **Immediate first heartbeat** after register in `LumenTerminalBridge.register()` — was a 0–30s "(waiting for snapshot…)" lag on first session view from iPhone. Now <1s.
- **Multi-buffer snapshot fallback** — try `.active` → `.alt` → `.normal` for `snapshotText()`. Claude Code's TUI lives in alt buffer; original code only read `.active` and got empty when Claude was running.

### Lumen security hardening

- **Launch face check is now MANDATORY.** Bug fix in `lumen_desktopApp.swift`: `restoreActiveSession()` no longer flips `isAuthenticated = true`. It still hydrates identity (so AuthGate doesn't ask for email again) but the face/PIN check is required every launch. Patrick reported app letting him in without any check.
- AuthGate defaults to `.face` mode (was `.passcode`).
- **`LumenPresenceMonitor`** — periodic silent face re-check (default every 20 min, headless `FaceCaptureSession` — camera blinks, no UI if face matches), idle lock after 5 min focus loss, manual lock via `⌃⌘L`. Lock view overlays MainView; app keeps running underneath (sync, terminal bridge, scheduled jobs all alive).
- **`PresenceLockView`** — face OR passcode unlock; mic + Eve voice killed when curtain drops.
- **Settings → PRESENCE & LOCK** panel.
- **2026-05-12 — Universal lock curtain**: every secondary WindowGroup (search palette, Eve orb, Console, conversation pop-outs, panels, Quick Capture, MenuBarExtra) now applies `.secondaryWindowCurtain()` modifier that drops opaque overlay when `!auth.isAuthenticated || presence.isLocked`. Patrick screenshotted Lumen on AuthGate while ⌘⇧K showed cached conversation snippets — fixed.

### Lumen chat UX

- **ConversationWindow rebuilt** (twice). Final state: 720×460 default with 200pt sidebar that's HIDDEN by default in pop-outs (collapsible). Single-line header (title + tiny "LUMEN · N messages" subtitle), no pill row, sidebar toggle + refresh on edges. Input bar **pinned to bottom** via `.fixedSize(horizontal: false, vertical: true)`; message list grabs `.frame(maxHeight: .infinity)`. Composer auto-grows from 24pt → 96pt (collapsed) or 200pt (expanded). Expand toggle inside the trailing edge of the field. Mic + send are 30pt circles flanking.
- **MainView right-side ASSISTANT panel** got the same fix in `LiveThreadView` — was the same root cause (composer floating mid-panel). `ComposerBar` is now `.fixedSize` vertically; `ConversationThread` grabs maxHeight infinity.
- **Header buttons rebuild** — SEARCH / POP OUT / END & NEW were rendering as cramped wrapped text (`tracking(1.5)` + narrow panel = bulbous looking circles with text wrap). Switched to icon-only 28x28 squares with `.help()` tooltips.
- **Screen-lock curtain on pop-out windows** — `DistributedNotificationCenter` observer for `com.apple.screenIsLocked`/`Unlocked` drops black "LOCKED" overlay on the pop-out content.

### Lumen build pipeline — finally stable signing

- **Root cause of recurring "Camera silently denied":** install pipeline was `ditto → PlistBuddy (CFBundleName) → codesign --force --sign <cert>`. The PlistBuddy step modified Info.plist AFTER xcodebuild signed, then I re-signed. Each install produced a new codesign hash → CoreMediaIO refused camera frames silently.
- **Fix 1:** Baked `CFBundleName = Lumen` + `CFBundleDisplayName = Lumen` directly into source `lumen-desktop/Info.plist` (was `$(PRODUCT_NAME)` which resolved to `lumen-desktop`). No more PlistBuddy needed.
- **Fix 2:** Added `DEVELOPMENT_TEAM = 773PKETJ85` to both Debug + Release configs in `lumen-desktop.xcodeproj/project.pbxproj`. Was missing → `CODE_SIGN_STYLE = Automatic` fell back to ad-hoc. Now xcodebuild signs directly with Apple Development cert; no post-build resign.
- **Install pipeline is now just `ditto build/.../lumen-desktop.app /Applications/Lumen.app && lsregister -f`.** No codesign, no PlistBuddy. Signature stays exactly what xcodebuild produced. Same Team ID + bundle ID across all future rebuilds → CoreMediaIO should persist the camera grant.
- Patrick may still need `tccutil reset Camera nexus.lumen-desktop` once to clear the stale ad-hoc entries from prior installs.

### Lumen polish

- Dashboard greeting pulls `LumenAPIManager.shared.activeUserFirstName` instead of hardcoded "Director." (Eve's system prompt already forbade honorifics; the UI hadn't gotten the memo.)
- Endpoint docs entry "Director-defined directives" → "Operator-defined directives".

### Lumen on iPhone — Phase 1 complete + most of Phase 3

Phone app went from ~5 screens to a full operational control surface. **11 tabs**: Eve / Dash / Ops / Agents / Sched / Term / Map / Brain / Connect / Brief / Arena.

**Per-tab scope:**
- Operations: list (search + +NEW) + detail (status cycle, edit sheet, add record, generate brief, kick research per record, timeline view)
- Agents: list (search + +NEW) + detail (Run Now, toggle active/standby, edit sheet, activity)
- Schedules: list (search + +NEW) + per-row enable toggle + Run Now per row
- Terminals: list (Lumen-spawned PTYs) + detail viewer + command submission
- Nexus Map: **2D Canvas force-directed graph** (hub-and-spoke by type, edges from `MapEdge` data, colored orbs) — matches Lumen's 3D SceneKit visual; plus list mode toggle for scanning
- Brain: Memory + Directives — list / search / +NEW / delete (deactivate); directives have per-row enable toggle
- Connections: read-only Arena OAuth providers
- Dashboard: 4-tile overview + recent Arena activity rail + active-research banner
- Briefing: existing
- Arena: status filter (All/Success/Error) + searchable

**Cross-cutting:**
- Quick Capture FAB on every non-Eve tab (drops a thought through `voice.sendText`)
- Global search palette in top bar (⌘ icon next to identity) — multi-source: conversations server-side via `/api/eve/search`, ops/agents/memories/schedules client-side
- Map node tap → detail sheet with cross-tab pivot
- Team list sheet (Command Center → Team) — read-only humans from nexus-map
- Settings deepening: Notifications section + 4 event toggles + permission state, REFRESH CADENCE picker, About (version/build)
- Active-conversation registration so dashboard Current Focus reflects pop-out windows

**Voice fluidity (Phase 3 win):**
- **Streaming TTS in `EveVoiceManager`** — sentence-boundary buffer reads streaming deltas; each completed sentence (`. ! ? \n`-terminated, ≥8 chars) fires its own `/api/eve/tts` fetch and queues the MP3. Sequential FIFO playback. First-sentence-spoken-time drops dramatically vs the old "wait for full reply then TTS the whole thing" flow. Feature flag `nexus.tts.streaming` default true.

**Brand:**
- App renamed from "nexus-ios" → **"Lumen"**. `INFOPLIST_KEY_CFBundleDisplayName = Lumen` in pbxproj for main + watch targets. Camera/Face-ID usage strings updated to "Lumen".

**Bugs fixed:**
- **Double messages**: `stopListening()` in EveVoiceManager wasn't idempotent. Silence timer fires → cancel recognition task → recognition callback fires error → calls stopListening AGAIN → submits the same transcribedText twice → two user messages. Guard on `recognitionTask != nil`, capture+clear transcribedText before submission.
- **Face capture orientation**: switched from `.leftMirrored` Vision hint to setting `connection.videoOrientation = .portrait` + `isVideoMirrored = true` on both video data output and photo output connections. More reliable across iOS versions.

### nexus-web

- **Trash2 import added** to `components/dashboard/ConsoleClient.tsx`. Was causing production dashboard render error `ReferenceError: Trash2 is not defined`. **LOCAL ONLY — NOT pushed to git, not deployed.** `portal.maxnexus.io` still shows the error.

### Memory rules locked in this session

Saved to `~/.claude/projects/-Users-shadow/memory/`:
- `feedback_ios_must_match_desktop.md` — iOS visuals must match Lumen, don't substitute a "phone-native" reimagining without explicit ask.
- `feedback_lumen_naming.md` — both apps are "Lumen" (no "Lumen iOS"/"Lumen Desktop"/"nexus-ios" user-visible).
- `feedback_evaluate_all_chat_surfaces.md` — chat UX fixes must touch ALL composer call sites.
- `feedback_lumen_build_install.md` — never mutate Info.plist after codesign; CoreMediaIO will deny camera every install.
- `feedback_no_honorifics.md` — no "Director", "sir", "ma'am" in user-visible strings.
- `feedback_curtain_every_window.md` — every Lumen WindowGroup must apply `.secondaryWindowCurtain()`.


---

## 2026-05-13 — Portability cleanup + B-1 decision

**Trigger:** Patrick tried running Nexus on a friend's Mac. Friend's `vercel` CLI bounced asking for `o-nexus` access (his GitHub doesn't have it).

**Diagnosis:** Two unrelated portability issues:
1. **Hardcoded `/Users/shadow/...` paths** in `scripts/launchd/*.plist`, `Claude-Vera.command`, and `newsyslog-nexus.conf`. `vera install` was copying these verbatim into `~/Library/LaunchAgents/`, so they only ever worked on Patrick's machine.
2. **Vercel "nexus-web" project's Git source is `patrickcmaxwell/o-nexus`** (the legacy v0.app repo) instead of this repo. So any `vercel deploy` from a clone authenticates against the wrong repo. This is the long-standing blocker B-1.

**Done in this session:**
- Plists + newsyslog conf templated with `__REPO_ROOT__` / `__LOG_DIR__` / `__USER__`; `vera install` now `sed`-substitutes at copy time. Same rendered output on Patrick's machine (byte-identical), works on anyone else's.
- `Claude-Vera.command` derives `REPO_ROOT` from its own location instead of hardcoding `cd /Users/shadow/code/nexus`.
- Added `.env.example` for `nexus-web/` and `arena/` (keys + grouping, no values). `arena-web/.env.example` already existed.
- README gained a "Bootstrap on a new Mac" section.
- Deleted stray `nexus-web/README 2.md` (was the auto-generated o-nexus v0 README accidentally copied in).
- **B-1 decision: Option A.** Patrick to repoint Vercel's `nexus-web` project at `patrickcmaxwell/nexus` (root `nexus-web/`). Vercel dashboard work only; no code change needed. After ~1 week healthy, archive `o-nexus` on GitHub.

**Owner of remaining work:** Patrick — Vercel dashboard repoint per `mission/blockers.md` #1.

---

## 2026-05-13 (later) — Face auth evolution: auto-learn on confident matches

**Trigger:** Patrick: "face recognition still not working properly. mission fix face auth nothing else matters." Then: "evolve it so people check in with new ones so the system recognition software learns the persons face with different angles or attire. Also angles should matter."

**Diagnosis (audit-only, full report in conversation):** Patrick's `humans` row had **one** stored descriptor (`face_descriptor` column), enrolled 16 days ago (2026-04-27), with **0** entries in `face_descriptors[]` and **null** `seed_face_descriptor`. Compare to Siggy (5 frames + seed). Single stale descriptor + camera change (NexiGo external is the user-preferred camera; enrollment was likely on a different camera) pushes match distance over the 0.6 mismatch threshold often enough to feel "still not working." Server pipeline (face-api WASM + sharp + 3-source matching + threshold 0.6) is sound; failure is in the data.

**Phase 1 shipped:**
- `nexus-web/app/api/security/face/match/route.ts` — on a confident match (distance ≤ 0.4, well inside the 0.6 gate), fire-and-forget append the live probe descriptor to the matched human's `face_descriptors[]` if (a) array has < 20 entries AND (b) probe is at least 0.15 distance from every existing reference (diversity guard). Errors never block the auth response.
- Same logic added to `nexus-web/app/api/security/face/route.ts` (web verify path).
- No schema migration. No client changes. Existing JSONB column reused.
- Effect: every successful login from Lumen / web grows the reference set with whatever Patrick's face looked like at that moment (lighting, angle, glasses, beard, hat). Over time the set covers his real variations without him going through enrollment again.

**Tunables in code:**
- `AUTO_APPEND_THRESHOLD = 0.4` — only learn from clearly-good matches
- `DIVERSITY_MIN_DISTANCE = 0.15` — don't bloat with near-duplicates
- `MAX_STORED_DESCRIPTORS = 20` — cap so the JSONB array can't grow unbounded

**Phase 2 planned (not shipped):** Client captures face yaw/pitch/roll via Vision landmark detection, sends with the match request. Server stores it in a sibling `face_descriptor_meta` JSONB column (additive migration). Matching uses orientation similarity as a tiebreaker. See `mission/pending-changes.md` for the full task.

---

## 2026-05-13 (late) — Deep security + UX/UI + supply-chain audits

**Trigger:** Patrick: "you sure you full audit everything from good UX practices and UI and security. i mean security."

**Three parallel agents ran. Findings logged in `mission/blockers.md` §0 (security) and noted in this entry.**

**Application-layer security — FIVE new CRITICAL findings:**
- **0-NEW-A.** `/api/groups/route.ts:12` lets any signed-in user enumerate/modify/delete ANY group. Multi-tenancy hole.
- **0-NEW-B.** PIN hash is `crypto.createHash("sha256")` — no salt, no bcrypt/argon2. 4-digit PIN space = 10K SHA256s, fully precomputable.
- **0-NEW-C.** PIN comparison uses `!==` — not timing-safe.
- **0-NEW-D.** Zero rate limiting on `/api/security/{pin,face/match,passphrase/check}`. `ip_blocklist` table exists but never written.
- **0-NEW-E.** Next.js 16.2.0 has 8 active HIGH-severity CVEs (middleware bypass, SSRF, cache poisoning). Upgrade to 16.2.6+.
- Plus 8 more HIGH/MEDIUM items (invite-token expiry, webhook plaintext, cookie sameSite, session refresh, EXIF strip, Eve LLM data disclosure, postcss XSS, Eve tool-arg validation).

**UX/UI:** No central toast/notification system. No confirm dialogs on delete actions. Loading skeletons missing on operations/map/humans dashboards. Forms missing `autocomplete`/`autoFocus`. iOS/Lumen touch targets below 44pt in several places. `muted-foreground` text contrast ~2.5:1 (WCAG AA needs 4.5:1). 23 `aria-label` instances across 200+ TSX files.

**Dependencies:** 16 vulns total in nexus-web (8 HIGH, 6 MODERATE, 2 LOW). Next.js bump clears 8 CVEs. PostCSS transitive XSS = `pnpm update` fix. No GPL/AGPL, no typosquats, lockfiles clean.

**Stopship for prod:** The groups multi-tenancy hole + SHA256 PINs + zero rate limiting together constitute a complete account-takeover kit. Do not invite anyone else onto the platform until at least 0-NEW-A, B, C, D are fixed. `mission/path-to-live.md` Stage 7 expanded scope substantially.

**No code changes shipped this round** — audit-only per directive.

---

## 2026-05-13 (later still) — Bundles 1, 2, 4 shipped (security hardening)

**Trigger:** Patrick: "i trust you why are you not full auto, get going. tell me if there is a dilema."

**Shipped (Bundle 1 — Trivial wins):**
- `nexus-web/package.json`: Next.js 16.2.0 → ^16.2.6. Same upgrade picked up automatically in arena-web + maxnexus-public (already `^16.2.0`). Clears 8 HIGH-severity CVEs (CVE-2026-23869 / 44575 / 44573 / 45109 + cache poisoning + SSRF variants).
- `pnpm update postcss --latest` across all three Next.js projects → ^8.5.14. Clears CVE-2026-41305 (XSS in CSS stringify).
- **PIN compare timing-safe:** new `nexus-web/lib/auth/pin.ts` exports `hashPin()` + `timingSafePinEqual()`. Rewired:
  - `app/api/security/pin/route.ts`
  - `app/api/security/reverify/route.ts`
  - `app/api/auth/switch/route.ts`
  - `app/api/auth/change-pin/route.ts`
- **Sign-up form a11y:** `app/auth/sign-up/page.tsx` — added `id` + `htmlFor`, `autoFocus` on email field, `autoComplete="email"`/`new-password`, `inputMode="email"`. Password managers now fill the form.
- **Dark-theme contrast:** `globals.css:28` — `--muted-foreground` bumped `oklch(0.55 0.02 210)` → `oklch(0.72 0.02 210)`. Pushes body-text contrast over WCAG AA 4.5:1.

**Shipped (Bundle 2 — Groups multi-tenancy):**
- `app/api/groups/route.ts` rewritten. GET now returns only groups the caller created OR is a member of (no workspace-wide enumeration). PATCH + DELETE check `created_by === currentHumanId` first, return 403 otherwise.

**Shipped (Bundle 4 — Rate limiting):**
- New `nexus-web/lib/auth/ratelimit.ts`. Uses `@upstash/ratelimit` + `@upstash/redis` (newly added deps). Per-endpoint sliding windows: PIN 10/5min, face 30/5min, passphrase 20/5min, generic 60/5min. Per-IP keyed via X-Forwarded-For.
- Wired into:
  - `app/api/security/pin/route.ts` (POST)
  - `app/api/security/face/match/route.ts` (POST)
  - `app/api/security/face/route.ts` (POST — verify + enroll paths)
- Degrades to no-op when `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN` are not set; logs one boot warning. Prod must set both. `/api/passphrase` is already disabled (HTTP 410) so not wired.

**Deferred (Bundle 3 — PIN bcrypt rotation):**
- Migrating from SHA256 → bcrypt requires (a) installing bcrypt, (b) accepting both hash formats during a transition window, (c) rehashing on next successful PIN entry, (d) eventually dropping the SHA256 path. Patrick is currently authenticated via the SHA256 path; misimplementation = lockout. Holding for a session where Patrick can verify each step before we cut over.

**Smoke-tested after shipping:**
- `/api/security/pin` → UNKNOWN_EMAIL (correct, route compiles)
- `/api/groups` → 401 unauth (correct, gate intact)
- `/api/security/face/match` → 400 missing body (correct, ratelimit doesn't fire on first request)
- `[ratelimit] UPSTASH_REDIS_REST_URL/_TOKEN not set — rate limiting DISABLED` warning seen as expected.

**What this resolves from `mission/blockers.md` §0:**
- 0-NEW-A (groups multi-tenancy) — FIXED
- 0-NEW-C (PIN timing-safe compare) — FIXED
- 0-NEW-D (no rate limiting) — INFRASTRUCTURE LANDED, awaits Upstash Redis env vars in prod to actually engage
- 0-NEW-E (Next.js 16.2.0 CVEs) — FIXED (16.2.6)
- 0-NEW-L (PostCSS XSS) — FIXED (8.5.14)

**Still open as critical:** 0-NEW-B (SHA256 PIN hash — needs bcrypt migration).

**Working tree:** 11 modified files + 2 new files (`lib/auth/pin.ts`, `lib/auth/ratelimit.ts`). Not committed, not pushed. Patrick to decide whether to commit + push (and let Vercel deploy after he repoints Stage 1).
