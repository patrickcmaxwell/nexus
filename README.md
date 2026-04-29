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

---

*Built for Patrick by Eve*
