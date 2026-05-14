# Active Blockers

Things blocking progress, with current workaround and what would unblock them.

---

## 0. Security debt surfaced in 2026-05-13 audits

Items that aren't blocking dev today but ARE blocking "give a friend access" or "publish portal.maxnexus.io openly." Each must be resolved before broadening access. Updated 2026-05-13 (late) after a deeper application-layer security audit.

### CRITICAL — fix BEFORE next prod deploy

#### 0-NEW-A. Groups endpoint multi-tenancy leak
**Where:** `nexus-web/app/api/groups/route.ts:12` — GET returns all groups without filtering by `created_by` or membership; PATCH/DELETE accept any authenticated session, no ownership check.
**Risk:** Any signed-in human can enumerate, modify, or delete ANY group in the workspace. Data exfiltration + privilege escalation.
**Fix:** Filter GET by `created_by = session.userId OR EXISTS (group_member where ...)`. Require ownership or admin role for PATCH/DELETE.
**Effort:** ~30 min.

#### 0-NEW-B. PIN hash uses raw SHA256, no salt
**Where:** `nexus-web/app/api/security/pin/route.ts:42` — `crypto.createHash("sha256").update(pin).digest("hex")`. Same in `/api/security/reverify` and `/api/auth/switch`.
**Risk:** 4-digit PIN space is 10,000 possibilities. SHA256 of every 4-digit string can be precomputed in seconds. If the `humans.pin_hash` column is ever leaked, ALL PINs are broken instantly.
**Fix:** Replace with bcrypt or argon2id; per-user salt (bcrypt does this). Schema migration to rehash existing pin_hashes on next login OR forced rotation.
**Effort:** 1-2 hrs incl. migration.

#### 0-NEW-C. PIN comparison not timing-safe
**Where:** Same files as 0-NEW-B — `human.pin_hash !== pinHash` uses `!==`, which short-circuits on first byte mismatch.
**Risk:** Timing side-channel leaks correct-prefix bytes one at a time. Theoretical but real.
**Fix:** `crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))`.
**Effort:** 5 min.

#### 0-NEW-D. No rate limiting on auth endpoints
**Where:** `/api/security/pin`, `/api/security/face/match`, `/api/security/face` (verify), `/api/passphrase/check`. An `ip_blocklist` table exists but is never written to.
**Risk:** Unbounded brute force. Attacker can spray 1M PIN guesses with zero friction. Combined with 0-NEW-B, this is a complete auth bypass kit.
**Fix:** Add Upstash Ratelimit (already a dep) or simple in-memory + Supabase-backed counter. Lock IP after N failures within window. Wire `ip_blocklist` table.
**Effort:** 2-3 hrs.

#### 0-NEW-E. Next.js 16.2.0 has 8 active HIGH-severity CVEs
**Where:** `nexus-web/package.json` + `maxnexus-public/package.json` pinned to 16.2.0. arena-web is at 16.2.5 (also vulnerable but less).
**CVEs:** CVE-2026-23869 (Server Components DoS), CVE-2026-44575 (middleware/proxy bypass), CVE-2026-44573 (i18n route bypass), CVE-2026-45109 (Turbopack middleware bypass), redirect cache poisoning, SSRF via WebSocket upgrades.
**Fix:** Upgrade to **Next.js 16.2.6+**. Also bump postcss (transitive XSS CVE-2026-41305 in 8.4.31-8.5.9).
**Effort:** 30 min upgrade + test. Should be a no-op functionally.

### HIGH — fix BEFORE broadening to non-Director users

(Previously documented + new from deeper audit)

- **0a. Hardcoded Supabase service-role JWT in Lumen Swift** — see existing detail below.
- **0b. `next.config.mjs` silences TypeScript errors** — see below.
- **0c. ~10 nexus-web routes missing auth guards** — see below. Now confirmed: includes `/api/passphrase`, `/api/llm/models`, `/api/groups/{join,manage}`, `/api/schedules/runner`, `/api/operations/agents`. Re-grep to enumerate full list.
- **0d. Eve's `web_search` tool promised but not wired** — see below.
- **0e. Arena single shared `ARENA_SECRET` + self-declared caller** — see below.
- **0-NEW-F. Invite tokens never expire, no single-use enforcement.** `/api/admin/reset-credentials/route.ts:57` mints a 256-bit token; stored at `humans.invite_token`; no `expires_at`; no `redeemed_at`. Leaked email = permanent backdoor. **Fix:** add `invite_token_expires_at`, set 7-day TTL, clear after first redemption. ~30 min.
- **0-NEW-G. Webhook secrets stored plaintext + no per-provider HMAC.** Already known; ranked higher now that Arena is going live. `arena_connections.webhook_secret` plaintext. **Fix:** verify per-provider signature (`X-Hub-Signature-256` for GitHub, `stripe-signature`, etc.) using the provider's signing secret. ~2-4 hrs.
- **0-NEW-H. Session cookie `sameSite=none` in production** (`nexus-web/lib/auth/cookie.ts:25`). Only required for cross-subdomain — overly permissive default. **Fix:** default `lax`, override to `none` only on the multi-subdomain path. ~10 min.
- **0-NEW-I. Sessions never refreshed on activity; no logout-everywhere.** `security_sessions` expires 60 min from `created_at`; doesn't bump on use. No way to invalidate all sessions for a user. **Fix:** add `last_used_at` + sliding expiry; add `POST /api/security/logout?all=1`. ~1 hr.

### MEDIUM — fix BEFORE public launch (if ever)

- **0-NEW-J. Avatar uploads don't strip EXIF.** `/api/auth/avatar/route.ts` accepts data URLs but doesn't run them through `sharp().rotate().withMetadata({})` to drop GPS/camera/timestamp. **Fix:** add metadata strip to upload pipeline. ~30 min.
- **0-NEW-K. Eve's system prompt sends user memory + directives + operations to xAI/Anthropic on every request.** No explicit user disclosure that private data goes to a third-party LLM provider. **Fix:** product decision — either add explicit user consent screen, OR document in `/dashboard/settings/privacy` what gets sent where. ~30 min for the disclosure.
- **0-NEW-L. PostCSS XSS via unescaped `</style>` (CVE-2026-41305).** Transitive dep of Next.js. **Fix:** `pnpm update postcss` to ≥ 8.5.10 across all three Next.js projects. ~10 min.
- **0-NEW-M. JSON.parse on Eve tool args without validation.** `/api/eve/route.ts:702` parses `tc.function.arguments` raw. If Grok returns shell metacharacters in `terminal_send` args, they hit Lumen's PTY unsanitized. **Risk requires:** Grok to be jailbroken AND Lumen to not sanitize on its side (it should, but defense-in-depth). **Fix:** add JSON schema validation per tool (zod). ~2 hrs.

### Detail — existing items 0a-0e (referenced above)

#### 0a. Hardcoded Supabase service-role JWT in Lumen Swift
**Where:** `lumen/lumen-desktop/lumen-desktop/SupabaseClient.swift:8-9`. The JWT is committed and in git history.
**Risk:** Service-role JWT grants write access to every Supabase table. If the repo becomes public OR a Lumen-installed laptop is lost, full prod DB write is exposed. Comment says "trusted local app" — that's not the actual threat model.
**Fix:** Rotate the JWT in Supabase. Move the new value to `~/Library/Application Support/Lumen/secrets.json` or Keychain. Rewrite SupabaseClient to read it at runtime. Filter old JWT out of git history (`git filter-repo --invert-paths --replace-text`) or accept the burn and rotate.
**Owner:** Patrick. Highest blast radius unfixed issue in the codebase.

#### 0b. `next.config.mjs` silences all TypeScript errors
**Where:** `nexus-web/next.config.mjs` — `typescript: { ignoreBuildErrors: true }`.
**Risk:** 800-line Eve orchestrator + 70+ API routes + zero compile-time type safety in CI. Runtime errors ship to prod undetected.
**Fix:** Flip to `false`, run `tsc --noEmit`, burn down the fallout in one sitting (1–3 hrs estimated).
**Owner:** Patrick.

#### 0c. Multiple nexus-web API routes don't enforce auth
**Where:** Audit flagged `/api/search`, `/api/agents`, `/api/operations`, and ~7 more as missing `checkAuth`/`checkDesktopAuth`. (Re-grep needed to enumerate full list.)
**Risk:** Reachable directly if nexus-web is exposed without a reverse-proxy gate. Anyone hitting the URL gets data.
**Fix:** Sweep `app/api/**/route.ts`, add `checkAuth(req)` to every route except public ones (auth/face/pin/passphrase, health, OAuth callbacks). Consider a `withAuth` wrapper to make the default safe.
**Owner:** Patrick (or claim a session).

#### 0d. Eve's system prompt promises a `web_search` tool that isn't wired
**Where:** `nexus-web/app/api/eve/route.ts` — system prompt directive 5 mentions web search; `toolDefs` array does not include it.
**Risk:** Eve will either say tool-not-found or hallucinate "current events" answers.
**Fix:** Pick one — wire Tavily/Brave/Perplexity behind a `web_search` tool, OR delete the directive line so Eve stops claiming the capability.

#### 0e. Arena uses one shared `ARENA_SECRET` for all callers; `X-Arena-Caller` is self-declared
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
