# Operation Multi-User Cleanup — Sweep Legacy USER_ID Importers

**Status:** PENDING (filed 2026-05-06)
**Owner:** Director (Patrick) + Vera
**Why now:** Operation Multi-User landed the identity primitives (humans table, auth_id bridge, getActiveAuthId session helper). Operation Welcome Mat shipped the user-facing flows. But **9 files still import the legacy `USER_ID` constant** from `lib/operations/auth.ts` — the same orphan UUID baked in before multi-user existed. Every one of these is a potential data leak when non-owners (Londynn, Merlin, future invitees) hit those endpoints. Same root cause as the `/dashboard/maxwell` Sessions leak; same fix shape.

---

## The constant in question

```ts
// lib/operations/auth.ts
export const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"
```

That UUID = Patrick's `humans.auth_id`. Earlier endpoints used it as a hardcoded filter. Any route that uses it always returns Patrick's data, regardless of who's logged in.

---

## Importers (as of 2026-05-06)

### Category A — User-scoped UI surfaces (definitely leaky)

These return data that should be scoped to the calling human. Today they all return Patrick's. Fix is mechanical: replace `USER_ID` with `await getActiveAuthId()` from `@/lib/auth/session`, 401 when null.

| File | Surface | Leak severity |
|---|---|---|
| `app/api/mentions/search/route.ts` | `@`-mention picker across operations/agents/records | High — invitees see Patrick's whole graph |
| `app/api/operations/records/[id]/route.ts` | Single operation record CRUD | High — invitees can read/edit Patrick's records |
| `app/api/operations/records/[id]/research/route.ts` | Records' research jobs | High |
| `app/api/operations/[id]/briefs/route.ts` | Operation brief reads | High |
| `app/api/dashboard/overview/route.ts` | Dashboard counts/widgets | Medium — read-only but exposes scale |
| `app/api/eve/briefing/route.ts` | Eve's daily briefing personalization | High — Eve briefs Londynn with Patrick's day |

### Category B — Background workers (need explicit ownership semantics)

These run server-side, often triggered by cron or other API routes. Using Patrick's `USER_ID` as a hardcoded "system" identity may be fine for now, but should be:
1. Renamed to make the intent explicit (`SYSTEM_OWNER_ID` or read from env)
2. Or refactored to take the target user_id as a parameter

| File | Trigger | Decision needed |
|---|---|---|
| `app/api/operations/research/watchdog/route.ts` | Cron — checks stale research jobs | Probably needs to scan ALL users' jobs, not just Patrick's |
| `lib/operations/research-runner.ts` | Called from research API + cron | Should accept `userId` arg, not pull from constant |
| `lib/operations/eve-analyst.ts` | Eve analyst worker | Same — `userId` param |

### Category C — Already correct (don't touch)

`app/dashboard/layout.tsx` imports `getSessionMember` (not `USER_ID`) — that's the right session-aware helper. No work.

---

## Plan

### Phase 1 — Sweep Category A (user-facing leaks)
For each file, do the same surgery as the maxwell page fix:
1. Replace `import { USER_ID }` with `import { getActiveAuthId }` from `@/lib/auth/session`
2. Replace `USER_ID` references with `await getActiveAuthId()`
3. Add 401 guard when null
4. Verify with typecheck
5. Single bundled commit titled `op-multi-user-cleanup: scope user-facing endpoints to active human`

### Phase 2 — Decide Category B semantics with Director
Before touching workers, get a decision from Patrick:
- Should research-watchdog scan every active human's jobs, or only the owner's?
- Should research-runner / eve-analyst be per-user (each invitee gets their own analyst) or owner-only (Patrick is the only one with active operations)?
- This is a product call, not a code call.

### Phase 3 — Delete the constant
Once Categories A + B are migrated, delete `USER_ID` from `lib/operations/auth.ts` so it can't accidentally come back. Leave the file (other helpers like `isAuthed`, `getSessionMember` are still used).

---

## Verification

- After Phase 1, log in as Londynn and hit `/api/operations`, `/api/dashboard/overview`, `/api/eve/briefing`, etc. — should return her data (probably empty for a fresh user) NOT Patrick's.
- After Phase 2, confirm watchdog/runner behavior is intentional (whatever was decided).
- After Phase 3, `grep -r "USER_ID" app lib --include="*.ts"` returns nothing.

---

## Why deferred (not done in Welcome Mat)

Welcome Mat focused on entry-point UX (onboarding wizard, settings, avatars) so Patrick could start inviting his team. The data-leak sweep is a parallel concern — most of these endpoints are admin-ish surfaces non-owner invitees won't touch in the first session. But every additional invitee = more chance someone hits one of these and sees Patrick's stuff. Sweep before the team grows.
