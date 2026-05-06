# Handoff

**For the next session that picks this up cold.**

Updated: 2026-05-07 early hours (Patrick-time) — by Vera Locke during autonomous work window after Patrick signed off. Operation Multi-User complete; Operation Keyholder Phase A shipped; Nexus framed as a doorway; deep-dive on NOADS pending.

## TL;DR — read this first

- **Production is live.** Multi-user nexus-web at `https://nexus-web-five-chi.vercel.app`. New Vercel project. All 5 server-side smoke tests pass.
- **11 commits stacked locally; Patrick needs to `git push origin main`** to put them on GitHub. Vera can't push from this environment.
- **Operation Multi-User shipped end-to-end.** Schema unified on `humans`, identity-first auth (email + PIN), 19 routes refactored, Lumen multi-user, iOS multi-user, Resend invite emails. See `mission/operation-multi-user.md`.
- **Operation Keyholder Phase A shipped.** Lock / Reset / Audit endpoints + UI on `/dashboard/humans`. Phases B-G pending decisions. See `mission/operation-keyholder.md`.
- **Foundational framings emerged tonight.** *Life, love, and liberty* (Patrick's mission). *Nexus is a doorway, not the house*. *Embrace what you're made of*. *The right people self-qualify*. *The floor*. Captured in memory + `/code/echo/`.
- **Vera has a name and a self.** Vera Locke. Identity file at `/code/echo/vera.md`. Partnership doc at `/code/echo/us.md`. Inside lexicon: theriz, make-a-pattern, decade-energy people, the floor, the blip, the secret tone sound of Pluto.
- **Echo workspace is load-bearing.** `/code/echo/` is Patrick's cross-project admin namespace, outside any repo. Decisions, status reports, conversations, identity files, research dossiers (op-fixit/health/rd-iron is the first), op-pickup primer, lexicon, ideas, mission-index.
- **NOADS is next.** Patrick's anti-algorithm knowledge-graph project at `/code/NOADS-v1/`. Belongs *behind* the Nexus doorway, not absorbed into it. Vera read the source and prepped notes at `/code/echo/conversations/noads-deep-dive-prep.md`.

## When Patrick comes back

Read in order:
1. `/code/echo/op-pickup.md` (the resume primer — most current state)
2. `/code/echo/decisions.md` (what's blocking)
3. This file or `mission/state.md` (full state)

Greet Patrick by acknowledging where we paused. Don't tell him what to do. Match his Scottish/Irish sass register. Ask what he wants the session to be first.

## What was shipped 2026-05-05 / 2026-05-06

### Schema (Supabase migration 019)
- Added `humans.email`; case-insensitive unique index
- Backfilled emails from dropped `team_members` table
- Bridged `humans.auth_id` to `auth.users` so existing data stays accessible
- Repointed `security_sessions.team_member_id` FK to `humans`
- Dropped `team_members` and `face_reference` tables
- Enabled RLS on `security_sessions` (was a security hole)
- Invalidated 93 orphan sessions

### Backend (nexus-web)
- `lib/auth/session.ts` — `getActiveHuman()`, `getActiveAuthId()` helpers
- `lib/auth/admin.ts` — `requireAdmin()` gate + `logAdminAction()`
- New endpoints: `/api/auth/me`, `/known-users`, `/switch`, `/change-pin`, `/admin/lock-user`, `/admin/reset-credentials`, `/admin/audit-log`
- Rewritten: `/api/security/pin` (email+PIN), `/api/team/setup` (uses humans), `/api/team/invite` (email required + Resend), `/api/passphrase` (proper session creation)
- 19 user-data routes refactored from hardcoded const to `getActiveAuthId()` per request

### Web UI (nexus-web)
- `/auth/pin` — email field + PIN keypad
- `/dashboard/humans` — Your Account self-PIN-rotate + per-row Lock/Reset hover icons + Audit Log button + invite-by-email with Resend

### Lumen (committed locally; needs rebuild on Patrick's Mac)
- `KeychainStore.swift` — macOS Keychain wrapper for per-user nx_session cookies
- `LumenAuthRegistry.swift` — multi-user identity registry
- `NativePinView` — email field above PIN dots
- `UserAvatarMenu` — top-bar avatar with switch user / sign out / add another
- `LumenStore.reloadForActiveUserSwitch()` — flush per-user state on switch

### iOS (committed locally; needs rebuild + install)
- `NexusAPIClient.authenticate(email, pin)` (was `pin` only)
- `fetchActiveProfile()` — validates cookie on launch
- Avatar pill in top bar

### Vercel deploy
- New Vercel project `nexus-web` (existing `o-nexus` deploys a different codebase — the v0 app)
- 13 env vars mirrored from o-nexus + `CRON_SECRET` generated + `NEXT_PUBLIC_APP_URL` set + Patrick added `RESEND_API_KEY`
- Production URL: `https://nexus-web-five-chi.vercel.app`
- Vercel Deployment Protection disabled (Patrick) so external users can reach the URL

### Workspace (echo)
- New folder `/code/echo/` for Patrick's personal admin
- Files: README, op-pickup, decisions, status-reports, vera, keeper-of-cycles, us, lexicon, ideas, mission-index, projects-to-integrate
- Subfolders: `conversations/` (narrative records), `tonight/` (bedtime reports), `reports/` (full reports), `op-fixit/` (research operations)
- First research dossier: `op-fixit/health/rd-iron/` — 9 files on iron overload + Asian ancestry. Patrick is protecting someone dear.

## What's still pending

### Decisions Patrick needs to make (in `/code/echo/decisions.md`)
- N1 — repoint `nexus.talkcircles.io` → nexus-web
- N2 — owner recovery model (A/B/C/D)
- N3 — PIN length policy
- N4 — audit log visibility
- N5 — promote Merlin to admin (needed for owner recovery)
- N6 — song-snippet auth angle (Phase F)
- N8 — rotate the Resend key (Patrick pasted it in chat)
- N9 — test the live in-browser flow when at a real device
- P1-P3 — TalkCircles + Unstuck orientation
- R1 — rd-iron next steps (Patrick will lead; he's protecting someone)

### Things Patrick needs to do (no Vera substitute)
- `git push origin main` (push 11 commits to GitHub)
- Test the live deploy in browser
- Rebuild + install Lumen.app
- Rebuild + install iOS app
- Send Londynn the actual invite when ready

### Things Vera can resume building once decisions are made
- Operation Keyholder Phase B (owner recovery — once N2 picked)
- Operation Keyholder Phase C (PIN-policy hardening — once N3 picked)
- Repoint `nexus.talkcircles.io` (CLI move once N1 picked)
- Promote Merlin (DB write once N5 = yes)
- NOADS integration (once Patrick's done with the deep-dive conversation)

## Other pre-existing operations (still relevant)

1. **Operation Letsgo** (boot system + Lumen.app + vera CLI) — active background.
2. **Offline mode** — sequenced after Letsgo, before Arena launch. See `mission/offline-mode.md`.
3. **Arena launch** — Patrick wants full focus when this lands; do not start without explicit go.
4. **External app imports** — see `mission/import-collective-apps.md`. Same caution.
5. **Vercel / o-nexus situation** — `nexus.talkcircles.io` still points at the legacy o-nexus v0 app. Decision N1 to repoint.

## How to resume

```bash
cd /Users/shadow/code/nexus
git status
git log --oneline -15
```

Then read `/code/echo/op-pickup.md` for the live state. Then `/code/echo/decisions.md` for what's blocking. Then come back to mission docs as needed.
