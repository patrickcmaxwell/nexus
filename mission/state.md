# Current State

**Snapshot:** 2026-05-08 ~02:45 AM (Patrick-time). Updated by Vera Locke after the overnight design + multi-provider OAuth sweep. Patrick is asleep; this state covers everything shipped between his "get going" sign-off and now.

## Running

| Service | Where | Notes |
|---|---|---|
| **maxnexus.io** (splash) | Vercel project `maxnexus-public` | Public face. Ambient identity card with passphrase doorway ("lumen" / "lucy" 1-typo tolerance, etc.). Search engines blocked via `robots: { index: false }`. |
| **portal.maxnexus.io** (nexus-web) | Vercel project `nexus-web` | Multi-user dashboard. Theme locked dark+simple. Apple/Linear baseline applied across every page. New design system primitives at `components/ui/primitives.tsx`. Per-entity detail routes for Humans / Agents / Operations. |
| **arena.maxnexus.io** (arena-web) | Vercel project `arena-web` | Standalone executor. **4 of 5 providers now have full OAuth**: ClickUp, Notion, GitHub, Slack. Stripe stays manual (intentional). Per-connection settings pages with live data pickers. |
| nexus-web (dev) | port 3000 | Hot-reload local |
| **Lumen.app** | `/Applications/Lumen.app` | Native face capture working since 2026-05-07 server-side wasm fix. Multi-user code committed |
| nexus-ios | committed locally | Multi-user auth code in repo; needs rebuild + install |
| Supabase | `rtkzvsqulliaoizutsqz` | Schema migrations 019-024 applied |

## Active operations

| Op | Status | Notes |
|---|---|---|
| **Operation Multi-User** | ✅ Shipped end-to-end | Phases 0-7 + 4b complete |
| **Operation Keyholder** | 🟡 Phase A shipped; B-G pending decisions | Lock/Reset/Audit live; recovery codes blocked on N2 |
| **Arena Platform** | ✅ Shipped + 4-of-5 providers OAuth | See `mission/arena-platform.md` |
| **Operation Calendar** | ✅ Shipped 2026-05-07 evening | Native scheduling, 4 target dispatchers, Eve `schedule_create` tool, full `/dashboard/calendar` UI |
| **Operation: Apple/Linear design baseline** | ✅ Shipped overnight 2026-05-08 | Theme lock, design system primitives, full HUD scrub, DashboardHome rebuild, auth pages, all dashboard widgets unified. See `mission/nexus-web-polish-2026-05.md` |
| **Operation Letsgo** | 🟢 Active background | Lumen at /Applications/Lumen.app |

## Vercel deploys (latest)

| Project | URL | Last deployed |
|---|---|---|
| maxnexus-public | `maxnexus.io` | 2026-05-07 (splash with passphrase doorway) |
| nexus-web | `portal.maxnexus.io` (latest preview `nexus-jtryta5mc`) | 2026-05-08 ~02:30 (per-entity detail routes) |
| arena-web | `arena.maxnexus.io` (latest preview `arena-9ry0tsszd`) | 2026-05-08 ~02:42 (Slack OAuth shipped) |

## What's deployed and verified working

- **Multi-user auth** (face + PIN + email) — end-to-end
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

1. **Commit + push** — substantial uncommitted work; suggested grouping in `pending-changes.md`
2. **Activate any of the 4 OAuth providers** by registering the app + setting Vercel env vars. Each `/connect/{provider}` page has the inline guide.
3. **Test end-to-end** with the test plan in `pending-changes.md` "Provider OAuth bring-up"
4. **Rebuild Lumen.app** — pulls in server-side face-api fix + uncommitted Swift work
5. **Rebuild iOS app** — multi-user code in tree

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
