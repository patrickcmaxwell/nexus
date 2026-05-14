# Path to Live — Nexus + Arena production cutover

**Created:** 2026-05-13. Consolidates state from `state.md`, `blockers.md`, `pending-changes.md`, `arena-platform.md`, and the 2026-05-13 full-project audit. This is the **canonical sequenced runbook** to get both Nexus and Arena from their current "partially live" state to "fully live and trustworthy."

---

## Goal

| Surface | Definition of "live" |
|---|---|
| **maxnexus.io** | Splash + passphrase door. Already live. No further work. |
| **portal.maxnexus.io** | Dashboard renders without errors; all auth modes work; agent scheduling runs in real prod mode (not dev-fallback); Eve can call Arena successfully. |
| **arena.maxnexus.io** | Health endpoint green; at least one OAuth provider (ClickUp) activated and verified end-to-end via Eve. |
| **Lumen.app (Mac)** | Pointed at `portal.maxnexus.io`; face auth working; presence lock working. |
| **Lumen (iPhone)** | Pointed at `portal.maxnexus.io`; signs in over cellular; Eve replies; Term tab can drive a Mac PTY. |

---

## Where we are right now (verified 2026-05-13 ~23:00)

| Check | Status |
|---|---|
| portal.maxnexus.io reachable | ✅ HTTP 401 on protected route (auth gate working) |
| arena.maxnexus.io/api/health | ✅ `{ok:true}`, 4 providers registered (ClickUp/Notion/GitHub/Stripe) |
| maxnexus.io | ✅ 307 redirect (expected — splash passphrase flow) |
| Vercel `nexus-web` Git source | ❌ `patrickcmaxwell/o-nexus` (should be `patrickcmaxwell/nexus`) |
| QStash + CRON_SECRET in Vercel | ❌ Missing → agent scheduling in dev-fallback in prod |
| ANTHROPIC_API_KEY in Vercel | ❌ Missing |
| Trash2 bug deployed | ❌ Local fix only; prod dashboard still crashes |
| OAuth providers activated | ❌ All 4 (ClickUp/Notion/GitHub/Slack) have code shipped, none have Client IDs in Vercel env |
| Lumen Supabase JWT hardcoded | ❌ `SupabaseClient.swift:8-9` (security debt) |
| `next.config.mjs` typescript silenced | ❌ `ignoreBuildErrors: true` (security debt) |
| ~10 nexus-web API routes lack auth | ❌ Sweep needed |
| Face auth evolution Phase 1 | ✅ Auto-learn shipped (local dev; needs prod deploy) |

---

## Stage 0 — Lock in the current working tree (5 min, Patrick or Vera)

**Why:** Mission docs + face auto-learn + audit findings are uncommitted. Cleanup commit `b949b81` already in. The remaining six modified files need to land before any deploy push so the audit/learnings persist.

**Files modified, uncommitted:**
- `PROJECT-STATUS.md` — audit security-debt summary
- `mission/blockers.md` — Section §0 (security debt) added
- `mission/journal.md` — 2 entries (portability + face evolution)
- `mission/pending-changes.md` — face Phase 2 + audit backlog
- `nexus-web/app/api/security/face/match/route.ts` — auto-learn block
- `nexus-web/app/api/security/face/route.ts` — auto-learn block

**Action:** `git commit` these as one logical unit ("face auto-learn + audit findings"), then `git push`.

**Acceptance:** `git status` clean. `origin/main` ahead of last `b949b81`.

---

## Stage 1 — Repoint Vercel (B-1 resolution, 10 min, Patrick)

**Why:** Right now, `git push origin main` does nothing for prod because Vercel's `nexus-web` project is connected to `patrickcmaxwell/o-nexus`, not `patrickcmaxwell/nexus`. The Trash2 fix and every change since are stranded. This is also why your friend's CLI got bounced.

**Action (Vercel dashboard):**

1. https://vercel.com → `nexus-web` project → **Settings → Git**
2. **Disconnect** from `patrickcmaxwell/o-nexus`
3. **Connect** to `patrickcmaxwell/nexus`
4. **Root Directory:** `nexus-web`
5. **Production Branch:** `main`
6. Save. Vercel will trigger a deploy from current `main` immediately.

**Acceptance:**
- Deploy logs show source = `patrickcmaxwell/nexus`
- Deploy succeeds
- `curl https://portal.maxnexus.io/api/dashboard/overview` still returns HTTP 401 (auth gate intact)
- Open `portal.maxnexus.io/dashboard` after signing in → no Trash2 ReferenceError in console

**Post-deploy:** Wait ~1 week of healthy deploys before archiving `patrickcmaxwell/o-nexus` on GitHub. Keep history; don't delete.

---

## Stage 2 — Backfill prod env vars (15 min, Patrick)

**Why:** Several features fall back to dev mode silently in prod because keys are missing. Best to add them all at once while you're in the Vercel dashboard.

**On the `nexus-web` Vercel project → Settings → Environment Variables, add (Production scope):**

| Key | Value | Source |
|---|---|---|
| `QSTASH_TOKEN` | (from console.upstash.com → your QStash queue) | Upstash dashboard |
| `QSTASH_CURRENT_SIGNING_KEY` | (same) | Upstash dashboard |
| `QSTASH_NEXT_SIGNING_KEY` | (same) | Upstash dashboard |
| `CRON_SECRET` | random 32+ char string | `openssl rand -hex 32` |
| `ANTHROPIC_API_KEY` | (from console.anthropic.com) | Anthropic dashboard |
| `NEXT_PUBLIC_APP_URL` | `https://portal.maxnexus.io` | — |

**Trigger a fresh deploy** after adding (Vercel → Deployments → ⋯ → Redeploy).

**Acceptance:**
- `curl https://portal.maxnexus.io/api/cron/agents -H "Authorization: Bearer $CRON_SECRET"` returns 200 (cron path is reachable + auth works)
- Trigger an agent scan from the dashboard → QStash dashboard shows the message published (vs dev-fallback)

---

## Stage 3 — Verify nexus-web prod path-to-Eve (10 min, Patrick)

**Why:** The Trash2 fix should now be live; the dashboard should render. Need a quick smoke test.

**Test plan:**

1. `portal.maxnexus.io` → sign in (PIN or face).
2. Dashboard renders. No Trash2 error in browser console.
3. Open EVE chat panel. Send "hi". Reply streams back. (Confirms `/api/eve` + Grok streaming on prod.)
4. Open `/dashboard/agents` → trigger Run Now on any agent. Confirms QStash dispatch.
5. Open `/dashboard/operations` and verify operations list loads.

**If any step fails:** stop, capture the error, and don't proceed. Issues at this stage indicate prod env var or build problems.

---

## Stage 4 — Activate Arena ClickUp OAuth (15 min, Patrick)

**Why:** Arena is deployed and healthy, but no provider is actually connected. ClickUp is the lowest-friction first activation (workspace-scoped, no review needed).

**Steps (already documented in `mission/handoff.md` and inline at `/connect/clickup`):**

1. ClickUp avatar (upper-right) → Settings → **Apps** → OAuth Apps → **Create new app**
2. **Redirect URL:** `https://arena.maxnexus.io/api/oauth/clickup/callback`
3. Copy Client ID + Client Secret.
4. Vercel → `arena-web` project → Settings → Env Vars → add (Production):
   - `CLICKUP_CLIENT_ID`
   - `CLICKUP_CLIENT_SECRET`
5. Redeploy `arena-web`.
6. Visit `arena.maxnexus.io/connect/clickup` → shows "Continue with ClickUp" button.
7. From portal Eve chat: *"create a clickup task called 'first prod test'"*
   - **Before connecting:** Eve should reply with the connect URL (not silent-mock).
   - **After connecting** + picking default list: Eve should reply with a real ClickUp task ID.

**Acceptance:** A real ClickUp task appears in your workspace, originated by an Eve call from prod.

---

## Stage 5 — Lumen + iOS pointed at prod (15 min, Patrick)

**Why:** Local dev path is already working. The question is whether prod URLs work the same from native apps.

**Lumen (Mac):**
- Open Settings → Endpoints. Set to `https://portal.maxnexus.io`.
- Sign out, sign back in via face. Face auth Phase 1 should auto-learn (watch web.log on portal — Vercel function logs — for `[face] auto-learned`).
- Send an Eve message. Confirm streaming.

**Lumen (iPhone), over cellular (not home Wi-Fi):**
- Settings → Endpoints → `https://portal.maxnexus.io`.
- Sign in via PIN (face on iOS still TBD per Phase 1 of nexus-ios parity).
- Send Eve message. Confirm reply arrives.
- Open Term tab → confirm Mac PTYs visible (terminal bridge over cellular).

**If either fails:** capture exact error. Most likely cause is a missing env var or CORS misconfig (`/api/desktop/dashboard` hardcodes `localhost:5173`; verify it isn't blocking the native client path).

---

## Stage 6 — Activate remaining 3 OAuth providers (15 min × 3, Patrick)

Same pattern as Stage 4. Each `/connect/{provider}` page has its inline admin guide.

| Provider | Developer portal | Required scopes |
|---|---|---|
| Notion | `notion.so/my-integrations` | (configured at app, not URL) |
| GitHub | `github.com/settings/developers` | `repo` |
| Slack | `api.slack.com/apps` | `chat:write,chat:write.public,channels:read,groups:read` |

**Skip Stripe.** Intentionally manual until Q1 product decision lands (high blast radius — payments).

---

## Stage 7 — Address audit security debt before broadening access (1-3 hrs, Patrick + Vera)

**Required before:** inviting anyone else to the system, making `portal.maxnexus.io` publicly indexable, or pushing the codebase to a public repo.

Each item full-detail in `mission/blockers.md` §0. Listed here in priority order:

1. **Rotate the Supabase service-role JWT** and move it out of `lumen/lumen-desktop/lumen-desktop/SupabaseClient.swift`. Load from Keychain at runtime. The current JWT is in git history; rotation invalidates the leaked value.
2. **Sweep nexus-web API routes for missing `checkAuth` / `checkDesktopAuth`** middleware. ~10 routes flagged by the audit. Add `withAuth` wrapper to make default safe.
3. **Flip `next.config.mjs` `typescript.ignoreBuildErrors`** to `false`. Run `tsc --noEmit`. Burn down the fallout in one sitting (estimated 1-3 hrs).
4. **Wire `web_search` tool** or remove the directive from Eve's system prompt. Currently she claims a capability she doesn't have.
5. **Defer Arena B-track** (per-caller tokens, scopes, rotation) until you actually invite a non-Director onto Arena. Until then, single shared `ARENA_SECRET` is acceptable but **rotate it from the default** and confirm `/api/health` no longer warns.

---

## Stage 8 — Face auth maturation (sequenced, not blocking launch)

**Phase 1 (shipped 2026-05-13):** Auto-learn on confident matches. Server-only, additive. Already in `nexus-web/app/api/security/face/{match,}/route.ts`.

**Phase 2 (planned, in `pending-changes.md`):** Client captures yaw/pitch/roll via Vision landmark detection; server stores in `face_descriptor_meta` JSONB sibling column; matching weights orientation similarity as a tiebreaker. Additive migration; backward-compatible.

**Stage 1 alone gets the user-visible improvement Patrick asked for** — every successful login grows the reference set with the variations encountered in real use. Phase 2 makes "angles matter" structurally.

---

## Out of scope for go-live (post-launch backlog)

- **Stripe activation** — keep mocked; revisit after 2 weeks of stable task-mgmt.
- **Push notifications** — iOS side wired; APN cert + backend dispatch pending.
- **Eve watches terminal sessions** — proactive alerts; needs push + cron infra.
- **iOS chat-UX parity v2** — 11 missing features (mention chips, slash, markdown, search, etc.).
- **Operation Documents** (PDF RAG) — substantial, not started.
- **Operation Keyholder Phase B-D** — blocked on N2 (owner recovery model decision).
- **External calendar sync** (Google/Apple) — ships as Arena providers.
- **Webhook HMAC verification per provider** — foundation exists; signatures deferred.
- **Connection-test cron** — auto-flip status before next Eve call discovers breakage.
- **Light-mode theme reactivation.**
- **Map / Suits / Systems pages** — last surfaces with intentional HUD aesthetic.

---

## Decision points blocking specific stages

| Decision | Blocks | Status |
|---|---|---|
| **N2** — owner recovery model (A/B/C/D approaches) | Keyholder Phase B onwards | Awaiting Patrick |
| **N3** — PIN length policy | Polish | Awaiting Patrick |
| **N5** — promote Merlin to admin | None (process) | Awaiting Patrick |
| **Q1** — Stripe OAuth: activate or keep manual? | Real payment routing | Awaiting Patrick. Default: keep manual. |

---

## Glossary

- **B-1**: the historical blocker that Vercel's `nexus-web` project deployed from `o-nexus` instead of `nexus`. Decision logged 2026-05-13 as "Option A — repoint." Stage 1 of this runbook executes that decision.
- **Track A / B / C** (Arena): A = ClickUp real wiring (done). B = per-caller auth hardening (deferred). C = deploy + smoke (mostly done — Vercel + arena.maxnexus.io live; no Dockerfile or smoke-test script).
- **Welcome-mat enrollment**: multi-frame face capture (front/left/right/up/smile) at `/dashboard/settings`. Only Siggy has been through this; everyone else has only the legacy single-descriptor enrollment.

---

## How a future session resumes this

1. Read this file top-to-bottom.
2. Check `mission/journal.md` for any 2026-05-13+ entries that update state.
3. Run the "Where we are right now" health checks at top to confirm what's still true.
4. Pick the next un-done stage. Execute.
