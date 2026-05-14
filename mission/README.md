# Mission Memory

The single source of truth for the **operational state** of Nexus across sessions.

Different from:
- `PROJECT-STATUS.md` — human-facing product/feature status (what works, what's next)
- `SESSION-LOG.md` — auto-appended commit log (noisy, gitignored)
- `memory/` — Eve's user-facing memory (Obsidian vault, conversation context)

## Files

| File | Purpose | Updated by |
|---|---|---|
| **`path-to-live.md`** | Canonical sequenced runbook to take Nexus + Arena from current state to fully live. **Start here.** | When stages complete or new ones surface |
| `state.md` | What is currently running, broken, in-flight, who is editing what | Each working session |
| `handoff.md` | If the session ended now, what would the next session need to know? | End of each session |
| `pending-changes.md` | Proposed code changes waiting on a condition (e.g. "apply when Xcode closed"). Each entry is a self-contained diff/snippet with the trigger | When a change is blocked |
| `blockers.md` | Active blockers with current workarounds and what would unblock them | Whenever a blocker appears or clears |
| `journal.md` | Append-only log of significant changes, decisions, and incidents | After meaningful work |

## Rule of thumb

If a fact would be useful to a future session that has no memory of this one, it goes here.
If it's only useful within the current session, leave it in conversation/tasks.
