# Handoff

**For the next session that picks this up cold.**

Updated: 2026-05-12 ~16:00 — after the multi-day Lumen + iOS heavy buildout. Prior overnight design + OAuth + per-entity sweep notes are still valid below; treat the additions as deltas.

## TL;DR (current — 2026-05-12)

- **Cross-device terminal bridge end-to-end working.** Mac PTYs visible + drivable from iPhone. URL mismatch (Lumen on legacy `nexus.talkcircles.io`, iOS on `portal.maxnexus.io`) was the bridge-blocker — now both on `portal.maxnexus.io`. Multi-buffer snapshot fallback (.active → .alt → .normal) handles Claude Code's alt-screen TUI.
- **Lumen security hardened.** Face check is now MANDATORY every launch (cookie restore no longer auto-passes). `LumenPresenceMonitor` adds periodic silent re-verify (default 20 min), idle-lock (5 min focus loss), manual `⌃⌘L`. Mic+voice kill on lock. **Universal lock curtain** drops on EVERY secondary window (search palette, Eve orb, console, pop-outs, panels, MenuBarExtra) when locked OR unauth'd — fixes the leak where ⌘⇧K on AuthGate showed cached conversation snippets.
- **Lumen build pipeline finally stable.** `DEVELOPMENT_TEAM = 773PKETJ85` set in pbxproj so xcodebuild signs with Apple Development cert directly (not ad-hoc). `CFBundleName/DisplayName = Lumen` baked into source Info.plist (no PlistBuddy). Install is now `ditto + lsregister`, nothing else. Same signature across builds → CoreMediaIO should finally persist camera grant. **One-time TCC reset may be needed** to flush stale ad-hoc entries: `tccutil reset Camera nexus.lumen-desktop` then relaunch.
- **Lumen chat UX rebuilt** after recurring "input takes 50% vertical" complaint. Root cause: `.fixedSize(horizontal: false, vertical: true)` missing on input HStack → composer inherited empty-message-list flex. Fixed in both pop-out `ConversationWindow` AND right-side `LiveThreadView`. Header buttons icon-only (was: cramped wrapping text).
- **Lumen on iPhone** ("Lumen" — renamed from "nexus-ios"): Phase 1 of parity roadmap COMPLETE. 11 tabs (Eve/Dash/Ops/Agents/Sched/Term/Map/Brain/Connect/Brief/Arena). Full CRUD on Ops/Agents/Schedules. Quick Capture FAB. Global search palette. Nexus Map 2D Canvas graph (matches Lumen's 3D SceneKit visual). Brain tab for Memory + Directives. Operation timeline view. Generate Brief sheet. Edit sheets. Team list. Streaming TTS (sentence-by-sentence playback for snappy voice).
- **nexus-web Trash2 bug NOT deployed.** Production dashboard render crashes with `ReferenceError: Trash2 is not defined`. Fix is in `components/dashboard/ConsoleClient.tsx` LOCALLY ONLY — needs `git push` + Vercel auto-deploy.
- **Old TL;DR (still valid):** Apple/Linear design baseline across nexus-web + arena-web. Per-entity detail routes for Humans/Agents/Operations. 4/5 Arena OAuth providers wired (ClickUp/Notion/GitHub/Slack; Stripe manual). Eve handoff for missing connections. Operation Calendar. Domains: `maxnexus.io` / `portal.maxnexus.io` / `arena.maxnexus.io`.
- **Working tree still has extensive uncommitted changes across nexus-ios + lumen + nexus-web.** Patrick needs to commit + push.

## When Patrick comes back

Read in order:
1. `mission/state.md` (current snapshot — most current)
2. `mission/pending-changes.md` (top entry: "Provider OAuth bring-up" — what Patrick needs to do)
3. `mission/arena-platform.md` (full state of Arena)
4. `mission/nexus-web-polish-2026-05.md` (catalog of UI/fix work)
5. `/code/echo/op-pickup.md` (cross-project resume primer)

## What's actionable now

### Immediate test path (5 min per provider)

**Activate ClickUp OAuth first** (template for the others):
1. ClickUp Avatar (upper-right) → Settings → **Apps** → scroll to OAuth Apps → **Create new app**
2. Redirect URL: `https://arena.maxnexus.io/api/oauth/clickup/callback`
3. Copy Client ID + Client Secret → arena-web Vercel env vars `CLICKUP_CLIENT_ID` + `CLICKUP_CLIENT_SECRET`
4. Visit `arena.maxnexus.io/connect/clickup` → should show "Continue with ClickUp" button
5. Eve test (BEFORE connecting): *"create a clickup task called 'first test'"* → should reply with the connect URL, not silently fail
6. Connect → pick default list → Eve test again → real task lands

**Repeat for Notion / GitHub / Slack** — each `/connect/{provider}` page has its own inline admin guide pointing at the right developer portal.

| Provider | Developer portal | Required scopes |
|---|---|---|
| ClickUp | `app.clickup.com/settings/apps` | (none — workspace scoped) |
| Notion | `www.notion.so/my-integrations` | (configured at app, not URL) |
| GitHub | `github.com/settings/developers` | `repo` |
| Slack | `api.slack.com/apps` | `chat:write,chat:write.public,channels:read,groups:read` |

### Drill-down detail routes to verify

- `portal.maxnexus.io/dashboard/humans/[id]` — click any member from `/dashboard/humans`
- `portal.maxnexus.io/dashboard/agents/[id]` — click any agent card
- `portal.maxnexus.io/dashboard/operations/[id]` — "Full view ↗" link in the operations master-detail header

### Other pending Patrick items

- Commit + push working tree (suggested groupings in `pending-changes.md`)
- Rebuild Lumen.app (server-side face-api fix is live; Swift work uncommitted)
- Rebuild iOS app (multi-user code in tree)
- Send invites to remaining decade-energy people

## What got shipped overnight (2026-05-07 evening → 2026-05-08 02:45)

### Round 1 — chat polish + suits→agents + Lumen face fix
See `mission/nexus-web-polish-2026-05.md` for the full file inventory.

### Round 2 — Arena ClickUp OAuth
- `lib/oauth/clickup.ts`, `/api/oauth/clickup/{start,callback,lists}`, `/connect/clickup` + settings page

### Round 3 — Theme lock + auth page sweep
- `useTheme.ts` locked to dark+simple
- Auth pages (PIN, face, error) HUD-stripped

### Round 4 — Notion OAuth (2nd provider)
- `lib/oauth/notion.ts`, `/api/oauth/notion/{start,callback,databases}`, `/connect/notion` + settings page

### Round 5 — Design system + DashboardHome rebuild
- `components/ui/primitives.tsx` — Card, Button, Input, Pill, Section, EmptyState, StatTile, Skeleton, Tabs
- Refined dark palette + Apple-style typography baseline
- DashboardHome rebuilt with 4-tile stats row + unified card surfaces across all 6 widgets

### Round 6 — Detail routes
- `/dashboard/humans/[id]` — profile / sessions / activity
- `/dashboard/agents/[id]` — profile / findings
- `/dashboard/operations/[id]` — overview / records / briefs

### Round 7 — GitHub OAuth (3rd provider)
- `lib/oauth/github.ts`, `/api/oauth/github/{start,callback,repos}`, `/connect/github` + settings page

### Round 8 — Slack OAuth (4th provider)
- `lib/oauth/slack.ts`, `/api/oauth/slack/{start,callback,channels}`, `/connect/slack` + settings page

## What's still pending

### Decisions Patrick needs to make
- N2 — owner recovery model (A/B/C/D)
- N3 — PIN length policy
- N5 — promote Merlin to admin
- N6 — song-snippet auth angle
- P1-P3 — TalkCircles + Unstuck orientation
- **Q1 (NEW)** — Stripe OAuth: activate or keep manual?

### Things Vera can resume building
- Per-provider HMAC signature verification on Arena webhooks (foundation exists)
- Connection-test cron (auto-flip status before next Eve call discovers breakage)
- External calendar sync (Google / Apple) as Arena providers
- Operation Mirror (cross-surface chat parity) — needs iOS rebuild first
- Operation Documents (PDF RAG) — substantial; not started
- Operation Keyholder Phase B-D once N2 lands
- Light-mode theme reactivation
- Map / Suits / Systems sweep (last HUD-aesthetic surfaces)

## How to resume

```bash
cd /Users/shadow/code/nexus
git status                        # see scope of uncommitted work
git log --oneline -10             # what's already in
cat mission/state.md              # current snapshot
cat mission/pending-changes.md    # top entry = what to do next
```
