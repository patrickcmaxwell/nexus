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
- Branch: (check with `git branch --show-current`)
- Last 2 commits: `32cd106 first version`, `8c1ca32 Initial folder structure` (April-ish — way out of date)
- **Vercel watches `patrickcmaxwell/o-nexus`, NOT this repo.** Prod deploys do not pick up changes here.

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
