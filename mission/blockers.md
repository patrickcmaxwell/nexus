# Active Blockers

Things blocking progress, with current workaround and what would unblock them.

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
