# Active Blockers

Things blocking progress, with current workaround and what would unblock them.

---

## 0. Security debt surfaced in 2026-05-13 full-project audit

Items that aren't blocking dev today but ARE blocking "give a friend access" or "publish portal.maxnexus.io openly." Each must be resolved before broadening access.

### 0a. Hardcoded Supabase service-role JWT in Lumen Swift
**Where:** `lumen/lumen-desktop/lumen-desktop/SupabaseClient.swift:8-9`. The JWT is committed and in git history.
**Risk:** Service-role JWT grants write access to every Supabase table. If the repo becomes public OR a Lumen-installed laptop is lost, full prod DB write is exposed. Comment says "trusted local app" — that's not the actual threat model.
**Fix:** Rotate the JWT in Supabase. Move the new value to `~/Library/Application Support/Lumen/secrets.json` or Keychain. Rewrite SupabaseClient to read it at runtime. Filter old JWT out of git history (`git filter-repo --invert-paths --replace-text`) or accept the burn and rotate.
**Owner:** Patrick. Highest blast radius unfixed issue in the codebase.

### 0b. `next.config.mjs` silences all TypeScript errors
**Where:** `nexus-web/next.config.mjs` — `typescript: { ignoreBuildErrors: true }`.
**Risk:** 800-line Eve orchestrator + 70+ API routes + zero compile-time type safety in CI. Runtime errors ship to prod undetected.
**Fix:** Flip to `false`, run `tsc --noEmit`, burn down the fallout in one sitting (1–3 hrs estimated).
**Owner:** Patrick.

### 0c. Multiple nexus-web API routes don't enforce auth
**Where:** Audit flagged `/api/search`, `/api/agents`, `/api/operations`, and ~7 more as missing `checkAuth`/`checkDesktopAuth`. (Re-grep needed to enumerate full list.)
**Risk:** Reachable directly if nexus-web is exposed without a reverse-proxy gate. Anyone hitting the URL gets data.
**Fix:** Sweep `app/api/**/route.ts`, add `checkAuth(req)` to every route except public ones (auth/face/pin/passphrase, health, OAuth callbacks). Consider a `withAuth` wrapper to make the default safe.
**Owner:** Patrick (or claim a session).

### 0d. Eve's system prompt promises a `web_search` tool that isn't wired
**Where:** `nexus-web/app/api/eve/route.ts` — system prompt directive 5 mentions web search; `toolDefs` array does not include it.
**Risk:** Eve will either say tool-not-found or hallucinate "current events" answers.
**Fix:** Pick one — wire Tavily/Brave/Perplexity behind a `web_search` tool, OR delete the directive line so Eve stops claiming the capability.

### 0e. Arena uses one shared `ARENA_SECRET` for all callers; `X-Arena-Caller` is self-declared
**Where:** Track B from `mission/arena-platform.md` — explicitly deferred. Single Bearer + unverified caller header.
**Risk:** Audit trail is fiction. The moment a non-Director gets a token, you can't tell who did what.
**Fix:** Don't invite anyone else onto Arena until `arena_callers` table + per-caller tokens land (B1-B4 from arena-launch.md).
**Owner:** Patrick — gate, not code fix today.

---

## 1. Two separate repos — Vercel deploys the wrong one for nexus-web work

**Status (2026-05-13):** Decision made — **Option A**. Patrick is repointing the Vercel `nexus-web` project at `github.com/patrickcmaxwell/nexus` (root `nexus-web/`). Accept loss of v0's auto-deploy flow. Trigger: friend tried `vercel` CLI from a clone and was bounced because the project's Git source is `o-nexus`, which he doesn't have access to.

**What:** `nexus` (this repo) and `o-nexus` (`~/code/ops/o-nexus`) were two active codebases:
- `github.com/patrickcmaxwell/nexus` — multi-surface canonical (this repo).
- `github.com/patrickcmaxwell/o-nexus` — v0.app Next.js app with 70+ merged v0 PRs. **Currently** the repo Vercel's `nexus-web` project is wired to.

**Resolution steps:**
1. Vercel dashboard → `nexus-web` project → Settings → Git → Disconnect, then connect to `patrickcmaxwell/nexus` with root directory `nexus-web/`.
2. While there, add the QStash + CRON env vars from blocker #2.
3. Trigger a deploy from `main` of `nexus` to confirm it picks up the new source.
4. Once healthy for ~1 week, archive `patrickcmaxwell/o-nexus` on GitHub (keep history for reference).

**Owner:** Patrick — Vercel dashboard work only, no code change needed in this repo.

## 2. QStash keys not in Vercel env

**What:** Autonomous agent scheduling falls back to dev-mode in prod because `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `NEXT_PUBLIC_APP_URL`, `CRON_SECRET` are missing from Vercel env vars.
**Workaround:** Local dev runs synchronously without QStash — no impact during development.
**Unblock:** Patrick adds keys from console.upstash.com to Vercel project settings.
**Owner:** Patrick (Vercel dashboard).

## 3. Lumen Swift edits in flight (Xcode active)

**What:** Xcode is debugging `lumen-desktop.app` live; codex agent has files open. Cannot edit Swift sources from outside without conflict.
**Workaround:** Queue changes in `pending-changes.md` and apply when Xcode is closed.
**Unblock:** Patrick stops the Xcode debug session.

## 4. ~~`.obsidian/workspace.json` and `graph.json` keep showing as dirty~~ — RESOLVED

Resolved by `.gitignore` entries (`**/.obsidian/workspace.json`, `graph.json`, `cache`). Confirmed 2026-05-13: those files no longer appear in `git status`.
