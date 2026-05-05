# Current State

**Snapshot:** 2026-05-04 (afternoon)

## Running

| Service | Port | Process | Notes |
|---|---|---|---|
| nexus-web (Next.js dev) | 3000 | next-server v16.2.0 | Hot-reload active |
| desktop Electron app | 5173 | vite + electron | `desktop/` — concurrent vite + electron via `npm run dev` |
| Lumen macOS app | n/a | Xcode (intermittent) | Director cycles `Cmd+R` between UI waves; not blocking right now |

## Editor activity (latest check)

- **Xcode** — not currently running (last check 2026-05-04 afternoon).
- **VS Code** — assumed open on `nexus-web/` and `desktop/`.
- **No Codex/Cursor processes detected.** Safe to edit Lumen Swift files when needed; re-check `pgrep` before each pass.

## Git state

- Remote: `https://github.com/patrickcmaxwell/nexus.git`
- Branch: `main`
- Recent commits (newest first):
  - `3f8f9d5` Updates to Desktop App
  - `b789885` mission: update state and journal after cleanup pass
  - `9dc300c` chore: mission memory + claude config + status doc
  - `c4c911e` memory: vault canvases and daily note
  - `591f138` desktop: Electron + Vite + React HUD app for nexus services
  - `fb2cf90` nexus-web: Bearer auth, agents pipeline, groups, security flows
  - `52a7ffe` chore: gitignore obsidian workspace state
- **Working tree mostly clean.** Untracked:
  - `mission/import-collective-apps.md` (Jarvis/IRIS/OpenJarvis import plan)
  - `mission/arena-launch.md` (this session — Arena launch tickets)
- **Vercel still watches `patrickcmaxwell/o-nexus`, NOT this repo.** Prod deploys do not pick up changes here. See `blockers.md` #1.

## Recent work (2026-05-03 → 2026-05-04)

Nine named "waves" of Lumen polish landed in the last 24-36h plus the desktop app refresh and Eve→Arena bridge. Highlights (full detail in `PROJECT-STATUS.md`):

- **Eve→Arena bridge live** — five Eve tools (`arena_task_create`, `arena_task_update`, `arena_payment_route`, `arena_sync_push`, `arena_recent`) wired and curl-verified end-to-end. Audit log table `arena_action_log` (migration 017) writing real rows. **External integrations still mocked** (see `arena-launch.md`).
- **Lumen — adaptive theme** — full light/dark sweep. `enum C` palette uses AppKit dynamic colors; 270 foreground occurrences flipped white→primary. `.preferredColorScheme(.dark)` removed everywhere. Detail windows (Conversation, Agent, Operation) now readable in light mode.
- **Lumen — multi-window pop-out** — any panel can detach into its own native macOS window. Per-conversation windows with independent send loops. Per-agent and per-operation windows with full feature parity. ⌘⌥1-7 shortcuts.
- **Lumen — 3D Nexus Map** — SceneKit universe view of all 525 nodes / 339 edges. Type clusters, glowing edges, orbit/pan/zoom, search, filters, click-to-open.
- **Lumen — voice tuning** — pause delays bumped to avoid cutting Eve off mid-thought; new connector pause for trailing conjunctions. Stop button on input bar when Eve is speaking.
- **Lumen — UI polish** — TopHUD slimmed and repurposed (live stats instead of branding), InputBar hides on non-chat panels, mention chip rendering with type-colored AttributedString tokens, Eve Brief generate button finally shows disabled state correctly.
- **Lumen — agent direct chat** — every agent has a DIRECT COMMS section that POSTs to `/api/agents/chat` using the agent's own role/personality as system prompt.
- **Lumen — sync actor** — `LumenSync.swift` 5s background tick with cadence-tuned refreshes (dashboard 20s, conversations 45s, etc.). ⌘R global "Sync now."
- **Vision parity across surfaces** — Lumen drag-drop image, Electron paperclip + drag-drop, iOS PhotosPicker. All route to llava:7b through `/api/eve/local`.
- **iOS** — PIN auth, voice picker (6 ElevenLabs voices), conversation history sheet, Control tab (remote agents/ops), direct LAN brain (skip nexus-web when on home wifi).
- **Electron Desktop** — `3f8f9d5 Updates to Desktop App` just landed. Functional but **shallower than Lumen** — fewer detail views, less data density. Identified as next UI polish target.

## Held (uncommitted, intentional)

The two new mission docs (`import-collective-apps.md`, `arena-launch.md`) are planning artifacts — commit when ready.

`mission/pending-changes.md` #1 (Lumen API key from env) still queued; cannot apply during Xcode debug. Apply on next quiet window.

## Health

- ✅ Local dev: nexus-web + desktop both running.
- ✅ Eve → Arena round-trip working end-to-end locally.
- ⚠️ Prod: detached from this codebase (Vercel wiring). Arena tools don't reach prod until resolved.
- ⚠️ Arena external integrations still mocked (ClickUp, Stripe, sync). See `arena-launch.md` for the path.
- ⚠️ Lumen API key still hardcoded; refactor queued in `pending-changes.md` #1.
- ✅ No real API keys in git.

## Architecture quick-ref (full version in root `README.md`)

```
You → Eve (persona) → Lumen / Desktop / iOS / Web (surfaces)
                          ↓
                       nexus-web (brain + APIs)
                          ↓
                  Arena (executor — tasks, payments, sync)
                          ↓
                  Vault (memory/ + Obsidian + Supabase)
```

Surfaces:
- **nexus-web** — Next.js, brain + APIs. Most complete.
- **Lumen** — SwiftUI native macOS. Feature-rich after May 3-4 waves.
- **Desktop** (Electron) — React + Vite. Functional, UI/data-density gap vs Lumen.
- **nexus-ios** — early but rising; vision + voice + control all live.
- **Arena** — Express executor. Wired, external integrations mocked.

## Active mission docs

- `state.md` — this file. Current snapshot.
- `blockers.md` — active blockers (Vercel/o-nexus is the big one).
- `pending-changes.md` — patches waiting on a condition.
- `handoff.md` — for the next cold session.
- `journal.md` — chronological notes.
- `import-collective-apps.md` — Jarvis/IRIS/OpenJarvis import plan (4 phases).
- `arena-launch.md` — Arena launch tickets (3 tracks: ClickUp, auth, deploy).

## Top-of-mind next actions

1. **Resolve Vercel/o-nexus** (`blockers.md` #1) — gates prod Eve→Arena.
2. **Track A from `arena-launch.md`** — real ClickUp wiring (~1 day's work).
3. **Electron desktop UI/data uplift** — port Lumen's detail-card + activity-log patterns into React.
4. **Apply `pending-changes.md` #1** — Lumen API key from env (next time Xcode is quiet).
