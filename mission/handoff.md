# Handoff

**For the next session that picks this up cold.**

Updated: 2026-05-05 (evening) — by Vera. Operation Multi-User shipped end-to-end.

## TL;DR — read this first

Operation Multi-User is **code-complete and committed locally**. Director needs to:

1. `cd ~/code/nexus && git push origin main` — pushes 8 commits, triggers Vercel auto-deploy of nexus-web
2. Set `RESEND_API_KEY` on Vercel (Resend creds Director said he'd share)
3. Run the 7-step test checklist in `pending-changes.md` (top entry)
4. If all 7 pass → invite Londynn from `/dashboard/humans` → multi-user is live

Lumen is already installed at `/Applications/Lumen.app` and ready to test. iOS code is committed but Director has to rebuild + install on his phone when ready.

The 8 local commits are:
```
580db84 multi-user: cron scans every user's agents + self-service PIN rotation
4e0100d multi-user: send invite email via Resend on team invite creation
d5e4328 mission: Operation Multi-User checkpoint + state refresh
528648e ios: multi-user auth + tool call cards + voice work
b790ce1 lumen: dashboard rework + voice fluidity + code panel + multi-user
5457bcc multi-user: web UI for email+PIN login + team admin
eb9e682 multi-user: data routes resolve user from session, not const
3bef603 multi-user: schema migration + identity-first auth foundation
```

## What was shipped this session

- **Schema unification** (Supabase migration 019): `humans.email` added, `team_members` + `face_reference` dropped, `humans.auth_id` bridged to auth.users, security_sessions RLS locked down, orphan sessions invalidated.
- **Identity-first auth**: `/api/security/pin` takes `{email, pin}` so PIN collisions across team members can't happen. New `/api/auth/me`, `/api/auth/known-users`, `/api/auth/switch`, `/api/auth/change-pin` endpoints.
- **All 19 user-data routes** refactored from hardcoded `USER_ID` const to per-request `getActiveAuthId()` resolution. Every API request scopes to the active human's data.
- **Web UI**: `/auth/pin` collects email + PIN with localStorage cache. `/dashboard/humans` admin (invite, role, disable). "Your Account" panel with self-service PIN rotation.
- **Invite emails** via Resend (lib/email/sendInvite.ts). Email lands when an invite is created; falls back to copy-paste if `RESEND_API_KEY` not set.
- **Lumen multi-user**: `LumenAuthRegistry` + `KeychainStore` (sessions in macOS Keychain), `NativePinView` with email field, top-bar avatar menu with switch + sign-out + add-another, `LumenStore.reloadForActiveUserSwitch()` flushes per-user state on switch.
- **iOS multi-user**: PinAuthView email field, `fetchActiveProfile` validates cached cookie on launch, avatar pill in top bar.

## Where we left off

Earlier mid-cleanup state (from 2026-05-04) is below for reference. Most of those items are still queued:

1. ~57 files dirty, ~17 untracked, only 2 commits ever — a lightning-strike risk.
2. Vercel watches the wrong repo (`o-nexus` instead of `nexus`) — prod is stale.
3. SESSION-LOG.md was being polluted by a Stop hook every session ending with no commits to actually log.
4. Two empty brace-expansion folders had been hanging around since April. ✅ Deleted.

## What's queued up to do

1. **Operation Letsgo (boot system)** — see `operation-letsgo.md`. Active focus. Lumen as standalone `/Applications/Lumen.app`, `vera` CLI for orchestration, launchd plists for nexus-web + arena + Ollama health, pause/resume for travel, drop VS Code dependency. **All open questions resolved**, decisions table in the doc. Ready to kick off.
2. **Offline mode** — see `offline-mode.md`. Sequenced after Letsgo, before Arena launch (Arena writes through nexus-web, so the outbox needs to exist first). Three layers: local credential cache, outbox+sync, network-aware routing. ~7 days of focused work.
3. **Arena launch** — see `arena-launch.md`. Director wants full focus when this lands; do not start without explicit go. Three tracks (ClickUp wiring, per-caller auth, deploy). Day 1 is `/task/create` real ClickUp call (`arena/src/index.ts:93-113`).
4. **External app imports** — see `import-collective-apps.md`. Director wants full focus when this lands; do not start without explicit go. Four phases pulling from IRIS-AI / OpenJarvis / Jarvis-Desktop.
5. **Lumen API key refactor** — see `pending-changes.md` #1. Apply next time Xcode is quiet.
6. **Vercel / o-nexus situation** — `nexus` and `o-nexus` are separate active repos, not fork/stale. See `blockers.md` #1. Patrick-owned architectural decision; gates prod Eve→Arena.
7. **Electron desktop work — PARKED.** Director paused this surface until explicitly requested. Focus is on Lumen + nexus-web + Operation Letsgo. Do not propose Electron tasks unsolicited.
8. **Commits in logical chunks** — see `journal.md` for grouping plan. Four new mission docs uncommitted: `arena-launch.md`, `import-collective-apps.md`, `operation-letsgo.md`, `offline-mode.md`. Plus modifications to `state.md` and `handoff.md`.
9. **Add `.obsidian/workspace.json` etc. to `.gitignore`** — local-only UI state shouldn't be tracked.

## How to resume

```bash
cd /Users/shadow/code/nexus
cat mission/state.md                    # what's running, what's open
cat mission/blockers.md                 # any active blockers
cat mission/operation-letsgo.md         # active: boot system + Lumen .app + vera CLI
cat mission/offline-mode.md             # next op after Letsgo: offline auth + outbox sync
cat mission/arena-launch.md             # major op (wait for Director go)
cat mission/import-collective-apps.md   # major op (wait for Director go)
git status --short                      # current dirty state
```

If Xcode is closed, check `mission/pending-changes.md` for any patches that were waiting to land.
