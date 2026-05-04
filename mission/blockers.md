# Active Blockers

Things blocking progress, with current workaround and what would unblock them.

---

## 1. Two separate repos — Vercel deploys the wrong one for nexus-web work

**What:** `nexus` (this repo) and `o-nexus` (`/Users/shadow/code/o-nexus`) are **not** fork/stale — they are two active codebases:
- `github.com/patrickcmaxwell/nexus` — multi-surface canonical (this repo). Vercel does not watch it.
- `github.com/patrickcmaxwell/o-nexus` — v0.app Next.js app with 70+ merged v0 PRs. **This is what Vercel deploys.**

So nexus-web work in this repo does not reach prod. Naively pushing this repo's history to o-nexus would fail or destroy v0 work — do not do it.

**Workaround:** None automatic. To get nexus-web changes to prod today, you'd have to mirror the relevant files into `/Users/shadow/code/o-nexus`, push from there.

**Unblock — architectural decision Patrick owns:**
- Option A: Repoint Vercel at `nexus`, accept losing `o-nexus`'s v0-friendly deploy flow.
- Option B: Keep `o-nexus` as the deployed face; treat `nexus` as the system-of-record and merge web changes into o-nexus periodically.
- Option C: Retire one entirely.

**Owner:** Patrick.

## 2. QStash keys not in Vercel env

**What:** Autonomous agent scheduling falls back to dev-mode in prod because `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `NEXT_PUBLIC_APP_URL`, `CRON_SECRET` are missing from Vercel env vars.
**Workaround:** Local dev runs synchronously without QStash — no impact during development.
**Unblock:** Patrick adds keys from console.upstash.com to Vercel project settings.
**Owner:** Patrick (Vercel dashboard).

## 3. Lumen Swift edits in flight (Xcode active)

**What:** Xcode is debugging `lumen-desktop.app` live; codex agent has files open. Cannot edit Swift sources from outside without conflict.
**Workaround:** Queue changes in `pending-changes.md` and apply when Xcode is closed.
**Unblock:** Patrick stops the Xcode debug session.

## 4. `.obsidian/workspace.json` and `graph.json` keep showing as dirty

**What:** Obsidian writes layout state to these files constantly. They're tracked in git and pollute every diff.
**Workaround:** Ignore in `git status` mentally.
**Unblock:** Add to `.gitignore` and `git rm --cached` them. Safe — they're per-machine UI state. (Will be done in cleanup.)
