# Current State

**Snapshot:** 2026-05-03 19:10 PDT

## Running

| Service | Port | Process | Notes |
|---|---|---|---|
| nexus-web (Next.js dev) | 3000 | next-server v16.2.0 | Hot-reload active |
| desktop Electron app | 5173 | vite + electron | `desktop/` — concurrent vite + electron via `npm run dev` |
| Lumen macOS app | n/a | Xcode debug session | PID 29019, lldb attached. **Active edits in progress — do not modify Swift files from outside Xcode.** |

## Editor activity

- **Xcode** open on `lumen-desktop.xcodeproj`, codex agent has files in `lumen/lumen-desktop/` open.
- **VS Code** open (window contents unknown — assume `nexus-web/` and `desktop/`).

## Git state

- Remote: `https://github.com/patrickcmaxwell/nexus.git`
- Branch: `main`
- Recent commits (newest first):
  - `9dc300c` mission memory + claude config + status doc
  - `c4c911e` memory: vault canvases
  - `591f138` desktop: Electron + Vite + React HUD app
  - `fb2cf90` nexus-web: Bearer auth, agents, groups, security
  - `52a7ffe` chore: gitignore obsidian workspace state
- **Not yet pushed to GitHub** — `git push origin main` when ready.
- **Vercel watches `patrickcmaxwell/o-nexus`, NOT this repo.** Prod deploys do not pick up changes here.

## Held (uncommitted, intentional)

These were not committed in the 2026-05-03 cleanup pass because their files were under live edit:

- `lumen/lumen-desktop/**` — 10 modified + 3 new Swift files. Xcode debugging active.
- `nexus-ios/**` — appeared dirty mid-session; something is editing live.
- `arena/**` and new `nexus-web/lib/arena/`, `nexus-web/lib/eve/`, `nexus-web/components/dashboard/home/ArenaActivityWidget.tsx`, `nexus-web/components/dashboard/DashboardHome.tsx`, `nexus-web/supabase/migrations/017_arena_action_log.sql` — appeared during the cleanup session, source of edits unknown (probably codex/cursor).

To commit these later, see `mission/handoff.md`.

## Health

- ✅ Local dev: nexus-web + desktop both running
- ⚠️ Prod: detached from this codebase (Vercel wiring)
- ⚠️ Many uncommitted changes — see `journal.md` for the catch-up plan
- ✅ No real API keys hardcoded (LumenAPIManager has placeholder only)

## Architecture quick-ref (full version in root `README.md`)

```
You → Eve (persona) → Lumen (brain) → Arena (executor)
                          ↓
                       Vault (memory/ + Obsidian)
```

Surfaces: nexus-web (Next.js), desktop (Electron), lumen (SwiftUI), nexus-ios (early).
