# Arena Launch Plan

> **⚠️ SUPERSEDED 2026-05-07 by `arena-platform.md`.**
>
> This document described the original Express-based single-file Arena service at `arena/src/index.ts`. That has been **fully replaced** by a standalone Next.js app at `/code/nexus/arena-web/`, deployed as its own Vercel project. The new design covers all five provider integrations (ClickUp, Notion, GitHub, Stripe, Slack), connection management UI, webhook receiver, audit log, and Eve introspection tools.
>
> Read `mission/arena-platform.md` for the current state. This file is preserved for historical context only — most of the launch tracks below have been replaced by completely different solutions.

---

**Created:** 2026-05-04
**Goal:** Get Arena from "wired but mocked" to "team-usable executor" so Eve can actually create ClickUp tasks, agents have caller-specific identities, and the service lives somewhere durable.

---

## Current state of Arena

`arena/src/index.ts` (181 lines, single file). Express + Bearer + Supabase audit log.

**Working today:**
- Bearer auth on every route except `/health` (lines 22-29).
- Action audit log writes to `public.arena_action_log` via Supabase REST (lines 39-62).
- Caller header `X-Arena-Caller` parsed and persisted (line 76).
- Five Eve tools call into Arena from `nexus-web/app/api/eve/route.ts` and round-trip end-to-end (curl-verified).
- Auto-loads `arena/.env` via `node --env-file=.env`.

**Mocked / not real:**
- `/task/create` (lines 93-113) — returns `MOCK-<timestamp>` instead of hitting ClickUp.
- `/task/update` (lines 115-126) — no-op success.
- `/payment/route` (lines 129-157) — validates split math, returns success without moving money.
- `/sync/push` (lines 160-175) — stub message.

**Auth model:**
- Single static `ARENA_SECRET` shared between nexus-web Eve, smoke tests, and any future caller.
- `X-Arena-Caller` is a *self-declared* string, not authenticated. Caller can claim to be anyone.
- Default secret `dev-arena-secret-change-me` warns in `/health` if unchanged.

**Hosting:**
- Local only. `localhost:3001`. No prod deploy.

---

## Launch tracks (parallelizable)

### Track A — Real ClickUp integration

The biggest unlock for "team task management." Eve already calls `arena_task_create` correctly; only the Arena handler needs to do the real work.

#### A1 — `/task/create` real ClickUp call
**File:** `arena/src/index.ts:93-113`

**Approach:**
1. Add `CLICKUP_API_KEY` and `CLICKUP_LIST_ID` to `arena/.env` (gitignored already).
2. Replace mock body (lines 101-106) with `fetch` to `https://api.clickup.com/api/v2/list/${listId}/task` POST.
3. Map Eve's params: `title → name`, `description → description`, `assignee → assignees: [user_id]`, `due → due_date` (ms epoch).
4. Resolve `assignee` (string username) → ClickUp user id via a small in-memory cache populated from `/team/${teamId}/member` on startup.
5. Return ClickUp's real `task.id` (e.g., `8amx9q`) instead of `MOCK-…`. The audit log row already captures whatever's returned, so no schema change.

**Acceptance:**
- `curl -X POST localhost:3001/task/create … -d '{"title":"…"}'` returns ClickUp's real id.
- Eve fires `arena_task_create` → task appears in the configured ClickUp list within seconds.
- `arena_action_log` row contains the real id in `result.task_id`.

**Estimate:** half day.

#### A2 — `/task/update` real ClickUp call
**File:** `arena/src/index.ts:115-126`

**Approach:** PUT to `https://api.clickup.com/api/v2/task/${task_id}`. Map Eve's `status`/`notes`. For notes, optionally POST a comment to `…/task/${id}/comment`.

**Acceptance:** Eve fires `arena_task_update` → status changes in ClickUp UI.

**Estimate:** 2-3 hours after A1 (auth + client are reusable).

#### A3 — Surface ClickUp errors back to Eve
**File:** `arena/src/index.ts:110-112` and Eve's tool result parsing in `nexus-web/app/api/eve/route.ts`

**Issue:** Current 500 handler returns `String(error)`, which strips ClickUp's actual error body. Eve then has no useful info to relay to the Director.

**Approach:** When ClickUp returns non-2xx, parse JSON body and include `clickup.err` / `clickup.ECODE` in the response. Eve's system prompt (DIRECTIVE 5 area) gets one line: "if a tool returns an error, surface the message verbatim before deciding next steps."

**Acceptance:** Try to assign to a non-existent user → Eve says "ClickUp rejected the task: USER_NOT_FOUND" instead of "task created."

**Estimate:** 1 hour.

#### A4 — `arena_recent` filter by ClickUp ids
**File:** `nexus-web/app/api/arena/log/route.ts`, Eve tool definition

**Why:** Now that real ids land in the audit log, Eve should be able to ask "show me the last 5 ClickUp tasks I created" and filter on `result.task_id LIKE 'CU-%'` (or whatever pattern emerges). Tiny query addition.

**Acceptance:** Eve can answer "what tasks did I just create?" with real ClickUp ids the Director can click through to.

**Estimate:** 1 hour.

---

### Track B — Per-caller authentication

Replace the single shared `ARENA_SECRET` with caller-specific tokens. Required before non-Director users touch the system.

#### B1 — `arena_callers` Supabase table
**Migration:** `nexus-web/supabase/migrations/018_arena_callers.sql`

```sql
create table public.arena_callers (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique,        -- 'eve', 'director', 'agent:sentinel', etc.
  token_hash    text not null,               -- bcrypt or sha256 of bearer token
  scopes        text[] not null default '{}',-- ['task:create','task:update','payment:route',…]
  human_id      uuid references humans(id),  -- null for non-human callers (eve, agents)
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz
);
create index on public.arena_callers (name) where active = true;
```

**Acceptance:** Migration applies cleanly. Seed rows: `eve`, `director`, `smoke-test`.

**Estimate:** 1 hour.

#### B2 — Arena auth middleware reads from Supabase
**File:** `arena/src/index.ts:22-29`

**Approach:**
- On startup, load active callers into an in-memory map (token_hash → {name, scopes, id}). Refresh on a 60s tick or on-demand via a `/admin/refresh` endpoint.
- `requireAuth` hashes the incoming Bearer token and looks it up. On match, attach `req.caller = {name, scopes, id}` to the request.
- Drop the `X-Arena-Caller` header — caller identity is now derived from the token, not self-declared.
- Update `arena_action_log` write to use `req.caller.name` instead of header value, and add `caller_id uuid` column referencing `arena_callers`.

**Acceptance:**
- Old single-secret flow still works as a fallback for one release (gated on `ARENA_LEGACY_SECRET=1` env var) so nothing breaks during cutover.
- Bad token → 401.
- Good token → request proceeds; `arena_action_log.caller` shows authenticated name.

**Estimate:** half day.

#### B3 — Per-route scope enforcement
**File:** `arena/src/index.ts` (each route)

**Approach:** Add `requireScope('task:create')` middleware after `requireAuth`. Returns 403 if the caller's scopes don't include the required scope.

**Default scopes:**
- `eve` → `task:*`, `sync:push`, `arena:read`. **No** `payment:*` (matches DIRECTIVE 5: "forbid unauthorized payments").
- `director` → all scopes.
- `agent:*` → `task:create`, `arena:read`. Read-only otherwise.

**Acceptance:** Eve attempting to call `/payment/route` → 403, audit row with `status=error, error_msg=missing scope payment:route`. The Director's CLI/curl can still fire it.

**Estimate:** 2 hours.

#### B4 — Token rotation script
**File:** `arena/scripts/rotate-token.ts` (new)

**Approach:** Small CLI: `npm run rotate-token -- --caller eve` → generates new token, updates `arena_callers.token_hash`, prints token once to stdout. Director copies into `nexus-web/.env.local` `ARENA_SECRET` (or new per-caller env var).

**Acceptance:** Compromised token can be rotated in under 60s without Arena restart.

**Estimate:** 1 hour.

---

### Track C — Deployment

Arena needs to live somewhere durable so Eve can fire tools when the Director's Mac is asleep, and so iOS / out-of-network surfaces can use it.

#### C1 — Pick a host

| Option | Pros | Cons |
|---|---|---|
| **Railway** | Simplest Node deploys, auto HTTPS, built-in env mgmt, ~$5/mo | Smaller ecosystem |
| **Render** | Similar to Railway, generous free tier | Free tier sleeps |
| **Fly.io** | Edge presence, scales to zero, cheap | More config (`fly.toml`) |
| **Vercel** | Already in use for nexus-web | Express server doesn't fit serverless well; would need to rewrite as Next.js API routes inside `nexus-web/app/api/arena/exec/` |

**Recommendation:** **Railway**. Cheapest path. Express stays Express. Connects directly to Supabase.

**Decision owner:** Patrick.

#### C2 — `arena/Dockerfile` + healthcheck
**File:** `arena/Dockerfile` (new)

Standard `node:20-alpine` build. `EXPOSE 3001`. Healthcheck hits `/health`.

**Acceptance:** `docker build && docker run` runs the same code that runs locally.

**Estimate:** 1 hour.

#### C3 — Domain + TLS
- Subdomain: `arena.nexus.<your-domain>` or Railway-issued URL until you decide.
- Update `ARENA_URL` in `nexus-web/.env.local` and Vercel env vars.

**Estimate:** 30 min after Track A is verified prod-ready.

#### C4 — Smoke test script
**File:** `arena/scripts/smoke.sh` (new)

Hits `/health`, `/task/create` (with disposable test list in ClickUp), `/task/update`, `/arena/log` (via nexus-web). Run after every deploy.

**Acceptance:** Single script gives ✓/✗ for every Arena capability post-deploy.

**Estimate:** 1 hour.

---

## Cross-cutting blockers

### B-1: Vercel watches `o-nexus`, not `nexus`
**See:** `mission/blockers.md` #1.

**Impact on Arena launch:** nexus-web's Eve tools (`arena_task_create` etc.) live in this repo. They don't reach prod until Vercel is repointed. Local Arena → local nexus-web works today; remote-anything is blocked on this decision.

**Patrick-owned decision.** No code change can route around it.

### B-2: ClickUp credentials
**Required before A1:** API key + a real list id to write into. Director's call which workspace/list to point at first.

### B-3: Supabase migration cadence
A1-A4 don't need migrations. B1 does. C-track doesn't. So migrations only land when Track B starts.

---

## Suggested execution order

```
Day 1 (low-risk, high-impact):
  ├─ A1: Real ClickUp /task/create
  ├─ A3: Surface ClickUp errors back to Eve
  └─ A2: Real ClickUp /task/update
        → At this point, Eve can drive a real ClickUp board.
        → Still single-secret auth, still localhost.

Day 2 (auth hardening):
  ├─ B1: arena_callers migration
  ├─ B2: Token-based auth middleware (legacy fallback gated)
  └─ B3: Scope enforcement
        → Now safe to give other humans tokens.

Day 3 (deploy):
  ├─ C1 decision: Railway (Patrick)
  ├─ C2: Dockerfile
  ├─ Resolve B-1 (Vercel/o-nexus) — UNBLOCKS prod Eve calling Arena
  ├─ C3: Domain + TLS
  └─ C4: Smoke test
        → Arena launched.

Day 4+ (deferred to post-launch):
  ├─ Real Stripe wiring on /payment/route (high blast radius — keep mocked until task mgmt is proven)
  ├─ Real /sync/push memory packaging
  ├─ B4: Token rotation script
  └─ Phase 3.2 from import-collective-apps.md: OpenJarvis Rust security scanner gating /payment/route
```

---

## Won't-do for launch

- **Stripe / payments** — keep mocked. Real money routing through a 3-day-old service is asking for an incident. Re-evaluate after 2 weeks of stable task-mgmt usage.
- **Crypto / bank transfer** — same reasoning, more so.
- **Slack / Linear / Jira connectors** — cherry-pick from OpenJarvis pattern (`import-collective-apps.md` Phase 1) only when there's actual demand.
- **Admin UI for callers/scopes** — Supabase Studio is the admin UI for now. Build dedicated UI when there are 5+ callers.

---

## Status

- [ ] **A1** — Real ClickUp `/task/create`
- [ ] **A2** — Real ClickUp `/task/update`
- [ ] **A3** — Surface ClickUp errors
- [ ] **A4** — `arena_recent` filter
- [ ] **B1** — `arena_callers` migration
- [ ] **B2** — Token auth middleware
- [ ] **B3** — Per-route scope enforcement
- [ ] **B4** — Token rotation script
- [ ] **C1** — Host decided
- [ ] **C2** — Dockerfile
- [ ] **C3** — Domain + TLS
- [ ] **C4** — Smoke script
- [ ] **B-1 (blocker)** — Vercel/o-nexus resolved

Update this file as items land. Cross-link incidents to `journal.md`.
