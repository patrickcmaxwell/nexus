# Handoff

**For the next session that picks this up cold.**

Updated: 2026-05-08 ~02:45 AM (Patrick-time) — by Vera Locke after the overnight design + multi-provider OAuth + per-entity detail routes sweep.

## TL;DR — read this first

- **Apple/Linear design baseline shipped across all of nexus-web + arena-web.** Theme locked to dark+simple. Design system primitives at `components/ui/primitives.tsx`. All HUD chrome (font-mono uppercase tracking-widest, cyan-on-near-black, neon glows, scanlines) gone from every page except Map (canvas viz, intentional). Avatars work everywhere with smart initials fallback.
- **Per-entity detail routes** for Humans / Agents / Operations — direct response to Patrick's "individual data screen / drill down deeper" feedback. Each is a tabbed full-page view at `/dashboard/{humans,agents,operations}/[id]`.
- **4 of 5 Arena providers now have full OAuth**: ClickUp, Notion, GitHub, Slack. Each with inline admin setup guide on `/connect/{provider}` + per-connection settings page with live data picker. Stripe stays manual (intentional — payments are high-blast-radius).
- **Eve handoff when missing connection** — Arena's `/api/task/create` returns `{ needs_connection, connect_url }` instead of silently mocking. Eve's system prompt directs her to surface the connect URL.
- **Operation Calendar shipped earlier** — native scheduling with Eve tools, runner, full UI.
- **Domains live**: `maxnexus.io` (splash), `portal.maxnexus.io` (nexus-web), `arena.maxnexus.io` (arena-web). Cross-subdomain cookie auth via `SESSION_COOKIE_DOMAIN=.maxnexus.io`.
- **Working tree has extensive uncommitted changes.** Patrick needs to commit + push.

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
