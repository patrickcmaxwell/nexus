# Active Blockers

Things blocking progress, with current workaround and what would unblock them.

---

## 1. Vercel deploys are stale

**What:** Vercel project watches `patrickcmaxwell/o-nexus` instead of `patrickcmaxwell/nexus`. Prod doesn't pick up nexus-web changes.
**Workaround:** None — prod is detached.
**Unblock:** Patrick reconnects Vercel project to `patrickcmaxwell/nexus` (Vercel dashboard → Project → Settings → Git).
**Owner:** Patrick (UI-driven, not scriptable from here).

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
