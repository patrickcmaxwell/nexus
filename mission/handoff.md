# Handoff

**For the next session that picks this up cold.**

Updated: 2026-05-04 (afternoon)

## Where we left off

Mid-cleanup of accumulated drift after weeks of building without committing. PROJECT-STATUS.md describes a full multi-surface AI OS that mostly works locally but has these structural problems:

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
