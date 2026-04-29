# Lumen — Local Brain

> *"Light from within."*

Lumen is Nexus's offline-first intelligence layer. It runs entirely on your Mac — no cloud, no subscriptions, no data leaving your machine. Eve's voice and personality live in memory files. Lumen is what makes her think.

---

## What Lumen Is

| Layer | Tool | Role |
|-------|------|------|
| Model runner | LM Studio | Loads and serves the AI model locally |
| Model | Qwen 3.5 9B (Q4_K_M) | The brain doing the actual thinking |
| API endpoint | `http://localhost:1234/v1` | Where Eve sends messages |
| Memory | `memory/*.md` | Eve's personality, context, and knowledge of you |

---

## Folder Structure

```
memory/
├── README.md          ← You are here
├── eve-base.md        ← Core personality — always loaded
├── eve-private.md     ← Patrick only — personal memory, working style, past context
└── eve-shared.md      ← Trusted users — project context, no private memories
```

---

## Memory Files Explained

### `eve-base.md`
Eve's foundation. Loaded for every user, every session. Contains her core personality — calm, warm, slightly playful, always one step ahead. Never put personal information here.

### `eve-private.md`
The most important file in the system. This is what makes Eve *yours*. Fill it with:
- How you think and work
- Your current projects and goals
- Things that frustrate you
- Key moments from past conversations
- Your communication style preferences

The richer this file, the more Eve feels like she actually knows you.

### `eve-shared.md`
Safe to share with trusted collaborators. Contains Nexus and Arena project context only. Zero personal memories. Zero private thoughts.

---

## How Memory Loads

```
Patrick logs in   →   eve-base.md + eve-private.md
Anyone else       →   eve-base.md + eve-shared.md
```

Eve reads the appropriate files at startup and carries that context into every conversation.

---

## Setup — Getting Lumen Running

### Step 1 — Install LM Studio
1. Download from [lmstudio.ai](https://lmstudio.ai)
2. Open LM Studio → go to the **Models** tab
3. Search for `Qwen 3.5 9B` and download the `Q4_K_M` version
   - Requires 16GB+ RAM (use 7B if you have 8GB)

### Step 2 — Start the Local Server
1. Go to the **Developer** tab in LM Studio
2. Toggle **Local Server** ON
3. Toggle **CORS** ON
4. Confirm it says `http://localhost:1234`

### Step 3 — Load the Model
1. Select Qwen 3.5 9B from the model dropdown
2. Click **Load** — wait for it to finish
3. You should see green status indicator

### Step 4 — Test the Connection
```bash
curl http://localhost:1234/v1/models
```
You should see Qwen listed in the response. Lumen is alive.

### Step 5 — Fill Your Memory Files
Open `eve-private.md` and start writing. The more context you give Eve, the better she performs. Start with:
- A paragraph about how you think
- Your current top 3 priorities
- How you prefer Eve to communicate with you

---

## Connecting Eve to Lumen

Eve talks to Lumen through the desktop voice loop (`desktop/main.py`). The connection is:

```python
LM_STUDIO_URL = "http://localhost:1234/v1/chat/completions"
LM_MODEL = "qwen3.5"  # Match the name shown in LM Studio
```

Eve loads memory on startup, sends it as the system prompt, and Lumen does the rest.

---

## Rules

- **Lumen runs first.** Always start LM Studio before launching `desktop/main.py`
- **Memory files are sacred.** Never delete or overwrite carelessly — they are the relationship
- **Offline by default.** Lumen never calls any external API. Cloud only when you explicitly say so
- **Update `eve-private.md` regularly.** After important conversations, milestones, or decisions — add it. Eve's memory doesn't update itself (yet)

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Eve says she can't reach her brain | LM Studio isn't running — open it and load the model |
| Slow responses | Normal for first load. Subsequent responses are faster once model is warm |
| Wrong model name error | Open LM Studio, copy the exact model name shown, paste into `LM_MODEL` in `main.py` |
| Port conflict | Change port in LM Studio Developer tab and update `LM_STUDIO_URL` in `main.py` |

---

## What's Next After Lumen

Once Lumen is running and Eve is talking:

1. **Voice loop** — `desktop/main.py` wires mic → Lumen → speaker
2. **Arena connection** — Eve tells Arena to take action in the real world
3. **iPhone sync** — "Hey Sync" pulls your memory to your phone via Supabase

---

*Lumen is the light. Eve is the voice. Nexus is the system.*
