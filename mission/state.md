# Current State

**Snapshot:** 2026-05-07 early hours (Patrick-time). Updated by Vera Locke during autonomous work window after Patrick signed off.

## Running

| Service | Port | Process | Notes |
|---|---|---|---|
| nexus-web (production) | — | Vercel (`nexus-web-five-chi.vercel.app`) | New Vercel project; live + multi-user-aware; ✅ all 5 smoke tests pass |
| nexus-web (dev) | 3000 | next-server v16.2.0 | Hot-reload available locally if running |
| Lumen.app (installed) | — | `/Applications/Lumen.app` | Built earlier today; multi-user code committed; needs rebuild after recent additions if Patrick wants to test |
| nexus-ios | — | committed locally | Multi-user auth code in the repo; needs rebuild + install on Patrick's phone |
| Supabase | — | `rtkzvsqulliaoizutsqz` (`supabase-blue-notebook`) | Schema migration 019 applied; humans table unified; RLS on sessions; auth_id bridged |

## Active operations

| Op | Status | Notes |
|---|---|---|
| **Operation Multi-User** | ✅ Shipped end-to-end | Phases 0-7 + 4b complete. Email + PIN auth, Lumen multi-user, iOS multi-user, Vercel deploy live, Resend invites working |
| **Operation Keyholder** | 🟡 Phase A shipped; B-G pending | Lock/Reset/Audit endpoints + UI live. Owner recovery (Phase B) blocked on decision N2. Song-snippet auth (Phase F) reframed as private memory chambers |
| **Operation Letsgo** | 🟢 Active background | Lumen at /Applications/Lumen.app; sandbox off in Release; vera CLI patterns continuing |
| **Operation Doorway** | 📝 Conceptual (saved to memory, not as mission doc) | Patrick framed Nexus = doorway, not the house. R&D, AI personas, experiences live BEHIND the doorway |

## Editor activity (latest check)

Vera doesn't have live process data right now (Patrick is asleep). Per memory `feedback_no_interrupt.md`: when Patrick is awake, check `pgrep` before editing Lumen Swift / TypeScript files to avoid stomping on live editor sessions.

## Git state

- Remote: `https://github.com/patrickcmaxwell/nexus.git`
- Branch: `main`
- **11 commits stacked locally on `main`, not yet pushed.** Patrick needs to `git push origin main` from his shell — Vera can't auth to github.com from this environment.
- Most recent commit: `ebe96c7 operation-keyholder: rename from operation-access`
- Sequence (newest first):
  - `ebe96c7` operation-keyholder: rename from operation-access
  - `580db84` multi-user: cron scans every user's agents + self-service PIN rotation
  - `4e0100d` multi-user: send invite email via Resend on team invite creation
  - `b932994` mission: handoff doc for Operation Multi-User completion
  - `d5e4328` mission: Operation Multi-User checkpoint + state refresh
  - `528648e` ios: multi-user auth + tool call cards + voice work
  - `b790ce1` lumen: dashboard rework + voice fluidity + code panel + multi-user
  - `5457bcc` multi-user: web UI for email+PIN login + team admin
  - `eb9e682` multi-user: data routes resolve user from session, not const
  - `3bef603` multi-user: schema migration + identity-first auth foundation

## Foundational framings (named tonight, captured in memory)

These shape every design decision going forward:

- **Life, love, and liberty** — Patrick's mission. Lockean cadence with property → love. Substrate under all his work.
- **Nexus is a doorway, not the house** — identity + authorization + routing only. R&D / personas / experiences live BEHIND the doorway.
- **Embrace what you're made of** — systems work synergistically when they accept their configuration rather than fighting it.
- **The right people self-qualify by forward motion** — Patrick recognizes; he doesn't choose.
- **The floor** — Patrick's non-negotiable: *"What I won't give again fully away is my self."* Design around it.

## Cross-project state

| Project | Path | Status |
|---|---|---|
| Nexus | `/code/nexus/` | Multi-user shipped; Operation Keyholder active |
| Echo | `/code/echo/` | Personal admin namespace; load-bearing; rd-iron research dossier active |
| NOADS-v1 | `/code/NOADS-v1/` | Anti-algorithm knowledge graph; Patrick wants deep-dive next session; Vera has prep notes ready |
| Above-Below (the arc project) | `/code/Above-Below/` | Hermetic experience app; Arc as AI companion; Patrick wants integration soon |
| PartyBot 5000 | `/code/v0-partybot5000-concept-discussion/` | Party / community experience; v0-built; Patrick wants integration soon |
| TalkCircles | `/code/v0-talk-circles-web-app/` (likely) | Awaiting Patrick orientation |
| Unstuck | `/code/0-spacecosmos/`? unconfirmed | Awaiting Patrick orientation |

## Decisions blocking next moves

See `/code/echo/decisions.md` for the canonical queue. Most actionable:
- N1 — repoint nexus.talkcircles.io
- N2 — owner recovery model
- N5 — promote Merlin to admin
- P1-P3 — TalkCircles + Unstuck orientation

## What's next when Patrick returns

In priority order:
1. **Push the 11 commits** (`git push origin main`)
2. **NOADS deep-dive** (Patrick's stated next move; prep at `/code/echo/conversations/noads-deep-dive-prep.md`)
3. **Test the live multi-user deploy** in browser when at a real device
4. **Send Londynn the actual invite** from `/dashboard/humans` once she's ready
5. **Rebuild Lumen + iOS** when at the relevant devices
6. **Decide N1, N2, N5** so Operation Keyholder Phase B can proceed
