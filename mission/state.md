# Current State

**Snapshot:** 2026-05-18. Patrick is active.

## Latest delta (2026-05-16 → 2026-05-18)

Three-day push consolidating auth, push notifications, terminal supervision, and user management. Everything below is committed and live on `portal.maxnexus.io`.

| Area | Status |
|---|---|
| **Auth overhaul (full)** | ✅ Shipped 2026-05-16. Invite-link domain bug (placeholder env var) fixed via new `lib/auth/origin.ts` — request origin wins over env. Field-name mismatch in `HumanDetailClient` admin actions fixed (`humanId` → `targetHumanId`). New endpoints: `/api/admin/unlock-user`, `/api/admin/clear-face`, `/api/admin/resend-invite`, `/api/admin/delete-human`, `/api/auth/forgot-pin`. New pages: `/auth/forgot` + "Forgot PIN?" link on `/auth/pin`. New helpers: `lib/email/sendPinReset.ts`. New UI: self-service face photo upload (`FacePhotoUploadModal`) in Settings (extracts descriptor client-side via face-api, optional "set as avatar"). Single-frame face enroll now APPENDS to `face_descriptors[]` (capped at 20) instead of writing only the legacy column — uploaded photos are actually matchable now. |
| **User management (complete loop)** | ✅ Shipped 2026-05-17. Humans list + detail page now expose every lifecycle action: invite → resend (non-destructive) → rotate-and-resend → lock ↔ unlock → reset PIN+face → clear face only → delete (type-name confirm). Owner self-recovery still via env-var passphrase only (intentional). |
| **`publicOrigin` precedence fix** | ✅ Shipped 2026-05-17. Inverted ordering — request origin beats `NEXT_PUBLIC_APP_URL`. `*.vercel.app` env values rejected so stale preview URLs can't poison invite emails. Hard fallback `https://portal.maxnexus.io` only when no request object available. |
| **Push notification pipeline** | ✅ Shipped 2026-05-16. Migration `027_push_devices.sql` (push_devices + push_log). `lib/push/dispatch.ts` — `sendPush(humanId, event, payload)` + `sendPushToAuthUser(authId, …)`, APNs HTTP/2 + ES256 JWT signing (cached 45min), automatic 410/BadDeviceToken row pruning, no-op `skipped/APNS_NOT_CONFIGURED` log when envs absent. `/api/push/devices` POST/GET/DELETE + `/api/push/test`. Hooked into `agents/process` finalize, `schedules/runner` success, `operations/research-runner` completion. iOS: `AppDelegate` via `@UIApplicationDelegateAdaptor`, `NexusPushClient` (enable/sendTestPush/syncPreferences/unregister), Settings UI with "Send test push" + token preview. **Patrick still needs to wire APN cert envs on Vercel** (`APNS_TEAM_ID`/`APNS_KEY_ID`/`APNS_KEY_PEM`/`APNS_TOPIC`); until then every dispatch records `skipped/APNS_NOT_CONFIGURED` in `push_log` so the audit trail is preserved. |
| **Eve terminal watcher v1** | ✅ Shipped 2026-05-16. Migration `028_terminal_watcher.sql` (terminal_watch_state + terminal_watch_log). `lib/terminal/classify.ts` — heuristic classifier returning `{kind, signature, excerpt}` where kind ∈ {blocker, confirm, done, idle}. Anchored confirm patterns on last non-empty line so old `(y/n)?` prompts don't re-fire. ANSI strip (CSI + OSC + charset). `/api/cron/terminal-watcher` bulk-loads active sessions, SHA1-hashes snapshots to skip unchanged, classifies, dedups against `(kind, signature)` with 30-min cooldown, fires `sendPushToAuthUser(userId, "terminal.alert", …)`, logs to `terminal_watch_log`. `vercel.json` cron at `* * * * *`. LLM upgrade is the v2 follow-up. |
| **iOS double-message bug** | ✅ Fixed 2026-05-16. Re-entrancy guard added to `EveVoiceManager.askHomeBrain` — second send during a streaming reply returns early with "Eve is still responding…" instead of running the full append-user → append-empty-eve → stream sequence again. Streaming chunks now track the bubble by UUID (`messages.firstIndex(where: { $0.id == bubbleId })`) instead of `messages.indices.last`, so concurrent mutations can't make chunks land in the wrong row. `submitTypedMessage` adds a UI-level haptic-error guard when `voice.isAwaitingReply` is true. |
| **nexus-web mobile/iPad composer responsiveness** | ✅ First pass shipped 2026-05-16. `MaxwellClient` composer: buttons shrink to 36×36 under 640px, Tag hidden under 640px, `min-w-0` on input so it actually shrinks, tighter gaps and padding. `EveCommand` session-mode header: `px-8`→`px-4` on small, footer wraps. Verify on iPad portrait + iPhone SE when convenient. |
| **`api/security/face/match` TS cleanup** | ✅ Shipped 2026-05-16. Three pre-existing TS errors fixed: `tf.setBackend`/`ready` cast through wide type, `sharp` default-import via `as unknown` coerce that respects esModuleInterop runtime, `faceapi.TNetInput` replaced with `Parameters<typeof faceapi.detectSingleFace>[0]`. Smoke-tested live: endpoint returns 400 on missing body (correct). |

## Latest delta (2026-05-13)

| Area | Status |
|---|---|
| **Repo portability cleanup** | ✅ Committed as `b949b81` ("fixed local"). Launchd plists templated with `__REPO_ROOT__`/`__LOG_DIR__`/`__USER__`; `vera install` substitutes at copy time. `Claude-Vera.command` derives REPO_ROOT from its own location. `.env.example` files for nexus-web + arena added. README has a "Bootstrap on a new Mac" section. Stray `nexus-web/README 2.md` (auto-copied o-nexus v0 README) deleted. |
| **B-1 decision (Vercel/o-nexus)** | Decision: **Option A** — repoint Vercel `nexus-web` project from `patrickcmaxwell/o-nexus` to `patrickcmaxwell/nexus` (root `nexus-web/`). Patrick-owned dashboard work; no code change needed. Trigger was a friend's `vercel` CLI bouncing on missing o-nexus access. |
| **Full-project audit** | Five-agent parallel survey done 2026-05-13. Findings logged in `mission/blockers.md` §0 (security debt) + `mission/pending-changes.md` (audit-driven backlog) + `PROJECT-STATUS.md`. Top issues: hardcoded Supabase JWT in `lumen/.../SupabaseClient.swift`; `next.config.mjs` `typescript.ignoreBuildErrors: true`; ~10 nexus-web API routes lack auth; Eve's `web_search` tool promised in system prompt but not wired; Arena single shared `ARENA_SECRET`. |
| **Face auth audit + Phase 1 evolution** | Diagnosed: Maxwell row had ONE 16-day-old `face_descriptor` (no `face_descriptors[]`, no `seed_face_descriptor`) vs Siggy's 5 frames. Plus camera-environment shift (NexiGo HD external is system-preferred camera now). **Phase 1 shipped (uncommitted in working tree):** `/api/security/face/match` and `/api/security/face` now auto-append the live probe to `face_descriptors[]` on confident matches (distance ≤ 0.4, diversity ≥ 0.15, cap 20). Fire-and-forget; never blocks auth response. Every successful login from Lumen now grows the reference set with the user's real variations (lighting, angles, glasses, beard, hat). |
| **Path to Live runbook** | Drafted at `mission/path-to-live.md`. 8 stages from current state to fully live (commit working tree → repoint Vercel → add prod env vars → smoke test → ClickUp OAuth → point native apps at prod → remaining 3 providers → security debt sweep). Use as reference, not mandate. |

## Latest delta (May 9 → May 12)

| Surface | Status |
|---|---|
| **Lumen.app** (Mac) | New build at `/Applications/Lumen.app` 2026-05-12. Properly signed with Apple Development cert (Team `773PKETJ85`). Stable signing pipeline (`ditto + lsregister` install only). |
| **Lumen on iPhone** | Phase 1 parity COMPLETE. App renamed "Lumen" (was "nexus-ios"). 11 tabs. Full CRUD. Streaming TTS shipped. Needs Xcode pull-and-build to deploy to device. |
| **Cross-device terminal bridge** | End-to-end working. iPhone Term tab → Mac PTYs. URL alignment + immediate-heartbeat + multi-buffer snapshot fallback. |
| **Lumen security** | Mandatory face check every launch. Presence monitor (periodic re-verify, idle lock, ⌃⌘L). Universal lock curtain on every window. |
| **nexus-web `portal.maxnexus.io`** | LIVE BUG: `Trash2 is not defined` dashboard render error. Fix in `ConsoleClient.tsx` local-only. Needs `git push`. |

## Running

| Service | Where | Notes |
|---|---|---|
| **maxnexus.io** (splash) | Vercel project `maxnexus-public` | Public face. Ambient identity card with passphrase doorway ("lumen" / "lucy" 1-typo tolerance, etc.). Search engines blocked via `robots: { index: false }`. |
| **portal.maxnexus.io** (nexus-web) | Vercel project `nexus-web` | Multi-user dashboard. Theme locked dark+simple. Apple/Linear baseline applied across every page. New design system primitives at `components/ui/primitives.tsx`. Per-entity detail routes for Humans / Agents / Operations. |
| **arena.maxnexus.io** (arena-web) | Vercel project `arena-web` | Standalone executor. **4 of 5 providers now have full OAuth**: ClickUp, Notion, GitHub, Slack. Stripe stays manual (intentional). Per-connection settings pages with live data pickers. |
| nexus-web (dev) | port 3000 | Hot-reload local |
| **Lumen.app** | `/Applications/Lumen.app` | Native face capture working since 2026-05-07 server-side wasm fix. Multi-user code committed |
| **Lumen on iPhone** (formerly nexus-ios) | Source updated 2026-05-12; needs Xcode rebuild + install on Patrick's iPhone | Renamed app to "Lumen". 11 tabs, full CRUD on Ops/Agents/Schedules, Brain tab (Memory+Directives), Map graph, Quick Capture FAB, Global Search palette, Streaming TTS, Team list. |
| Supabase | `rtkzvsqulliaoizutsqz` | Schema migrations 019-028 applied (027 push_devices + 028 terminal_watcher landed 2026-05-16) |

## Active operations

| Op | Status | Notes |
|---|---|---|
| **Operation Multi-User** | ✅ Shipped end-to-end | Phases 0-7 + 4b complete |
| **Operation Keyholder** | 🟢 Phase A + non-blocking follow-ups shipped | Lock/Unlock/Reset/Clear-face/Resend-invite/Rotate-resend/Delete-human + forgot-PIN email recovery all live (2026-05-16/17). Phase B owner-recovery codes still blocked on N2 decision. |
| **Arena Platform** | ✅ Shipped + 4-of-5 providers OAuth | See `mission/arena-platform.md` |
| **Operation Calendar** | ✅ Shipped 2026-05-07 evening | Native scheduling, 4 target dispatchers, Eve `schedule_create` tool, full `/dashboard/calendar` UI |
| **Operation: Apple/Linear design baseline** | ✅ Shipped overnight 2026-05-08 | Theme lock, design system primitives, full HUD scrub, DashboardHome rebuild, auth pages, all dashboard widgets unified. See `mission/nexus-web-polish-2026-05.md` |
| **Operation Letsgo** | 🟢 Active background | Lumen at /Applications/Lumen.app |
| **Operation Phone Buildout** | ✅ Shipped Phase 1 (2026-05-09 → 2026-05-12) | Lumen-on-iPhone went from ~5 screens to 11-tab operational control surface. See `project_nexus_ios_parity.md` in Claude memory for the full ledger. |
| **Operation Terminal Bridge** | ✅ End-to-end working (2026-05-12) | Mac PTYs visible + drivable from iPhone via `terminal_sessions` + `terminal_commands` polling. |
| **Operation Lumen Security** | ✅ Shipped 2026-05-09 → 2026-05-12 | Mandatory face on launch + presence monitor + universal lock curtain. |

## Vercel deploys (latest)

| Project | URL | Last deployed |
|---|---|---|
| maxnexus-public | `maxnexus.io` | 2026-05-07 (splash with passphrase doorway) |
| nexus-web | `portal.maxnexus.io` (latest prod `dpl_AnJ3QMpPS66VndkDDaVscbu2PKMh`) | 2026-05-17 (resend/delete admin actions + invite URL precedence fix) |
| arena-web | `arena.maxnexus.io` (latest preview `arena-9ry0tsszd`) | 2026-05-08 ~02:42 (Slack OAuth shipped) |

## What's deployed and verified working

- **Multi-user auth** (face + PIN + email) — end-to-end with full lifecycle (invite → resend → reset → unlock → delete)
- **Self-service PIN recovery** — `/auth/forgot` mints a reset token, emails via Resend, refuses on owner
- **Self-service face upload** — Settings → Face recognition → "Upload a photo" extracts descriptor client-side and appends to enrolled set
- **Push notification pipeline** — schema + dispatch + cron-event hooks live; APNs delivery awaits cert envs
- **Eve terminal watcher** — minute-cadence cron, heuristic classifier (blocker/confirm/done/idle), 30-min dedup cooldown, audit log
- **Cross-subdomain cookie auth** — sign in at portal, carries to arena (`SESSION_COOKIE_DOMAIN=.maxnexus.io` on both Vercel projects)
- **Lumen native face login** — server-side face-api uses node-wasm path
- **Splash passphrase doorway** — type lumen/lucy → portal redirect (1-char typo tolerance)
- **Calendar / scheduling** — schedule_create + schedule_list Eve tools, `/dashboard/calendar` UI, every-minute Vercel Cron runner, 4 target dispatchers (eve_chat / agent_run / operation_brief / arena_action), Run Now button + per-row history + next-3-firings preview
- **4 OAuth providers** — ClickUp, Notion, GitHub, Slack each have: `lib/oauth/{provider}.ts` helpers, `/api/oauth/{provider}/{start,callback,...}` routes, `/connect/{provider}` Apple-styled landing with inline 5-6-step admin guide, `/connect/{provider}/[id]/settings` with live data picker (lists/databases/repos/channels), legacy manual fallback at `/connect/{provider}/manual`
- **Eve handoff on missing connection** — `/api/task/create` returns `{ needs_connection, connect_url }` instead of silent-mocking; Eve's system prompt directs her to surface the connect URL
- **Per-entity detail routes** in nexus-web:
  - `/dashboard/humans/[id]` — profile / sessions / activity tabs + admin actions
  - `/dashboard/agents/[id]` — profile / findings tabs + Run Now
  - `/dashboard/operations/[id]` — overview / records / briefs tabs

## Design system foundation (NEW)

`components/ui/primitives.tsx` — opinionated atoms every page composes from:
- `Card` (5 padding × 5 tone variants)
- `Button` (5 variants × 3 sizes, with loading + iconLeft/Right + fullWidth)
- `Input`, `Pill` (6 tones × 2 sizes), `Section`, `EmptyState`, `StatTile`, `Skeleton`, `Tabs`

Avatars: `components/ui/UserAvatar.tsx` with deterministic colored-initials fallback. Wired into sidebar / Maxwell chat / Settings / Humans list.

Globals: refined dark palette (3-tier surface hierarchy, hairline borders, single deep-blue accent oklch 0.70 0.16 248), Apple-style optical typography (-0.011em tracking, tighter heading line-height, tabular numerals).

## Editor activity (latest check)

- **Xcode** running on lumen-desktop earlier (33709). Has likely been closed by now since Patrick is asleep.
- Editing nexus-web / arena-web TypeScript: safe.

## Git state

Working tree:
- `/code/nexus/nexus-web/` — extensive uncommitted work spanning the whole overnight design + detail-route sweep
- `/code/nexus/arena-web/` — extensive uncommitted work: 4 new OAuth providers + their settings pages + provider updates
- `/code/nexus/maxnexus-public/` — splash app (already committed earlier)
- `/code/nexus/mission/` — these doc updates

Patrick needs to commit + push before he loses this state to a stash mishap.

Remote: `https://github.com/patrickcmaxwell/nexus.git`. Branch: `main`.

## What needs Patrick's hand right now

In rough sequence (none blocking the rest):

1. **Wire APN cert envs on Vercel** to actually deliver push notifications. Set `APNS_TEAM_ID` (Apple Developer team ID), `APNS_KEY_ID` (APNs auth key ID), `APNS_KEY_PEM` (.p8 contents — newlines as `\n`), `APNS_TOPIC=com.maxwell.nexus-ios`, optionally `APNS_USE_SANDBOX=1` for development builds. Until set, every dispatch records `skipped/APNS_NOT_CONFIGURED` in `push_log`.
2. **Rebuild + install iOS app** to pick up double-message fix + push client + Settings UI updates.
3. **Activate any of the 4 OAuth providers** by registering the app + setting Vercel env vars. Each `/connect/{provider}` page has the inline guide.
4. **Test end-to-end** with the test plan in `pending-changes.md` "Provider OAuth bring-up"
5. **Rebuild Lumen.app** — pulls in server-side face-api fix + uncommitted Swift work
6. **Apply N2 decision** (owner self-recovery model) to unblock Keyholder Phase B

## Foundational framings (still active)

- **Life, love, and liberty** — Patrick's mission. Lockean cadence with property → love.
- **Nexus is a doorway, not the house** — identity + authorization + routing only. R&D / personas / experiences live BEHIND the doorway.
- **Embrace what you're made of** — systems work synergistically when they accept their configuration rather than fighting it.
- **The right people self-qualify by forward motion** — Patrick recognizes; he doesn't choose.
- **The floor** — Patrick's non-negotiable: *"What I won't give again fully away is my self."*
- **Drill down deeper** (NEW, this session) — every entity in the system should have its own full-page detail view. Master-detail panels are fine for browse, but a deep-link route is mandatory for share-ability and full review.

## Cross-project state

| Project | Path | Status |
|---|---|---|
| Nexus | `/code/nexus/` | Multi-user shipped; Arena platform + 4-OAuth live; design baseline overhauled overnight |
| Arena | `/code/nexus/arena-web/` | Standalone Next.js, 4 OAuth providers + 1 manual (Stripe) |
| maxnexus-public | `/code/nexus/maxnexus-public/` | Splash with passphrase doorway |
| Echo | `/code/echo/` | Personal admin namespace; load-bearing |
| Above-Below | `/code/Above-Below/` | Hermetic experience app; integration deferred |
| TalkCircles | `/code/v0-talk-circles-web-app/` | Awaiting orientation |
| Unstuck | TBD | Awaiting orientation |

## Decisions blocking next moves

See `/code/echo/decisions.md` for the canonical queue. Most actionable:
- **N2 — owner recovery model** (blocks Operation Keyholder Phase B)
- **N5 — promote Merlin to admin**
- **P1-P3** — TalkCircles + Unstuck orientation
- **Q1 (NEW)** — Stripe OAuth: do we want it now? Currently kept on manual API key intentionally because payments are high-blast-radius. Decision needed before flipping.

## What's next (in priority order)

1. **Patrick activates ClickUp OAuth + tests Eve→ClickUp** — proof-of-concept the whole multi-user provider story works end-to-end
2. **Then rinse: activate Notion + GitHub + Slack** — same pattern, ~5 min each
3. **Webhook HMAC verification per provider** — production-safety follow-up; receiver foundation exists, signature checks deferred
4. **Connection-test cron** — auto-flip status before next Eve call discovers breakage
5. **External calendar sync** (Google / Apple) — ships as Arena providers
6. **Operation Mirror** (cross-surface chat parity web/Lumen/iOS) — needs iOS rebuild first
7. **Operation Documents** (PDF RAG) — substantial; not started
8. **Operation Keyholder Phase B-D** once N2 lands
9. **Light-mode theme support** — currently locked to dark; reactivate when inline-style sweep is fully done
10. **Map / Suits / Systems pages** — last surfaces with intentional HUD aesthetic; Map is canvas viz, others are stylistic. Sweep when there's appetite.
