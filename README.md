# Nexus

My personal AI operating system. **Lumen** is the underlying brain and compute engine, while **Eve** is the persona and the protector of all systems.

## Architecture

```
You (Patrick)
     ↓ voice
   Eve ────────►  Arena
 (Protector)    (Executor)
     ↓ uses          ↑
 Lumen             External Services
 (Brain)           (ClickUp, Payments, Google…)
     ↑
 The Vault
 (Obsidian + Memory)
```

| Component | Folder | Role | Runs on |
|-----------|--------|------|---------|
| Lumen / Eve | `desktop/` + `memory/` | Lumen processes/thinks, Eve talks/protects | Mac (primary) + iPhone |
| Arena | `arena/` | Executes tasks, moves money, talks to tools | Server / Mac |
| The Vault | `memory/` + Obsidian | Long-term memory and knowledge base | Local files |
| iOS App | `nexus-ios/` | Global voice interface from anywhere | iPhone |
| Web App | `nexus-web/` | Web interface and backend | Web / Server |

## Core Rules

- **Offline-first** — everything runs locally by default
- Cloud (Grok API) only when I say "use grok", "use internet", or "go online"
- Eve must always sound calm, warm, and helpful
- iPhone must always have Apple Intelligence as a fast fallback

## How to Run

- `nexus-web/` → `npm run dev`
- Desktop voice → `python desktop/main.py` (LM Studio must be running first)
- Arena → `cd arena && npm run dev`

## Bootstrap on a new Mac

The repo is portable — nothing is pinned to `/Users/shadow`. Clone it anywhere
under your home directory and run:

```bash
# 1. Get the code
git clone <repo-url> nexus && cd nexus

# 2. Env files (ask Patrick for actual values)
cp nexus-web/.env.example nexus-web/.env.local
cp arena/.env.example arena/.env
cp arena-web/.env.example arena-web/.env.local

# 3. Node deps
(cd nexus-web && npm install)
(cd arena && npm install)
(cd arena-web && npm install)

# 4. Install Vera (orchestrator + launchd jobs)
./scripts/vera install
./scripts/vera up        # bring services online
./scripts/vera status    # verify

# 5. Build & install Lumen.app to /Applications
./scripts/build-lumen.sh
```

`vera install` materializes `scripts/launchd/com.nexus.*.plist` into
`~/Library/LaunchAgents/` with this machine's `REPO_ROOT` and `LOG_DIR`
substituted in — so no hand-editing required, regardless of where the repo
lives. Run `vera doctor` if anything looks off.

---

*Built for Patrick by Eve*
