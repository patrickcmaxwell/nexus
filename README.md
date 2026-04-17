# Nexus

My personal AI operating system built around **Eve**.

## Architecture

```
You (Patrick)
     ↓ voice
   Eve  ──────────────────►  Arena
 (Brain)                    (Executor)
     ↑                           ↑
 The Vault               External Services
 (Obsidian + Memory)     (ClickUp, Payments, Google…)
```

| Component | Folder | Role | Runs on |
|-----------|--------|------|---------|
| Eve | `desktop/` + `memory/` | Thinks, talks, predicts, knows me | Mac (primary) + iPhone |
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
