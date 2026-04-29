# Lumen — Desktop Application
### The Native macOS Control Center for Nexus

---

## What Lumen Desktop Is

Lumen is a full native macOS application that serves as the primary interface for the Nexus system. It is not a voice chatbot. It is not a dashboard. It is a complete operational environment where you can talk, type, manage, monitor, and control everything in Nexus — all from one native app.

**The brain behind Lumen is LM Studio** running locally at `http://localhost:1234/v1`. All AI thinking happens locally. No cloud required for core functionality.

**The backend is Nexus** — Supabase for data, Arena middleware at `http://localhost:3001` for operations and execution.

**Eve and Vera are personalities** — not agents, not bots. They are the voices and characters behind the system. Eve is the primary personality (built from conversations with Claude). Vera is a secondary personality (built from her own conversation history, imported separately). They both run on Lumen's local brain. They are part of the brain layer, not the agent layer.

---

## The Two Personalities

### Eve
- Primary voice and personality of the system
- Calm, warm, soothing, slightly playful
- Knows Patrick deeply — predicts his thinking, offers next steps before being asked
- Loaded from `memory/eve-base.md` + `memory/eve-private.md`
- Default personality for Patrick

### Vera
- Secondary personality (meaning "truth")
- Her own distinct voice and character
- Built from exported conversation history (imported separately)
- Loaded from `memory/vera-base.md` + `memory/vera-private.md`
- Can be switched to at any time

**Switching personalities:**
- Voice: "Switch to Vera" / "Switch to Eve"
- Or select from personality switcher in the UI
- Context from the current conversation carries over on switch

---

## How You Interact

This is not a single-mode app. You can:

- **Talk** — voice input via microphone, Eve/Vera responds via Kokoro TTS
- **Type** — full text input, same conversation thread
- **Click** — interact directly with operations, tasks, agents on screen
- **Mix** — talk sometimes, type sometimes, click sometimes — all in the same session

There is no "voice mode" and "text mode" — it's all one unified interface.

---

## Core Features

### 1. Conversations
- Start a new conversation with a topic/title
- Browse all past conversations in a sidebar
- Each conversation persists to Supabase — nothing is ever lost
- Conversations are searchable
- Tag conversations with topics or projects
- Voice and text messages both saved to the same thread
- Eve/Vera can reference past conversations when relevant

### 2. Operations Management
- See all active, paused, and completed operations
- Create new operations directly in the app (voice or click)
- Assign operations to agents
- Update operation status
- See which operations have stalled or been abandoned
- Eve can surface which operations need attention without being asked

### 3. Task Management
- See tasks inside operations
- Create, assign, update, complete tasks
- Tasks sync with ClickUp (via Arena)
- Ask Eve "what needs to be done next?" and she'll tell you based on real data

### 4. Agent Management
- See all agents running in Arena
- Monitor their status — what are they doing right now?
- Create new agents
- Assign directives to agents
- Define protocols (rules agents follow)
- Pause or stop agents

### 5. Lumen Brain Control
- See what model is currently loaded in LM Studio
- Switch models from within the app
- Monitor Lumen's performance (response time, load)
- See if Lumen is online/offline
- Restart Lumen if needed

### 6. System Control (Mac)
- Open and close apps
- Read and write files
- Monitor what's running
- Clipboard access — read/write
- Screen awareness — know what app is currently active

### 7. Humans (People Layer)
- See who's in your Nexus system
- Manage their access levels
- See their shared data and public operations
- Communicate with them

### 8. The Vault
- Browse your memory files
- Search your Obsidian knowledge base
- Update eve-private.md or vera-private.md
- See what Eve/Vera currently know about you

---

## UI Structure

### Main Screen (always visible)
- Conversation thread (center — dominant element)
- Voice waveform when listening
- Input field (text) at the bottom
- Personality indicator (Eve or Vera) top left
- Lumen status indicator (online/offline) top right
- Navigation sidebar (left) — collapsible

### Navigation Sidebar
- New Conversation button
- Past conversations list
- Operations
- Agents
- Humans
- The Vault
- Settings

### Animated Panels (slide in over main screen)
- Triggered by voice ("show me operations") or sidebar tap
- Never fully replace the main conversation view
- Scrollable content
- Dismiss by voice ("close that") or swipe/button
- Operations panel
- Agent status panel
- Task list panel
- Vault panel
- Lumen control panel

### Full Screen Mode
- Conversation takes the entire screen
- Minimal UI — just the waveform, current message, status
- For focused voice-first sessions
- Toggle with keyboard shortcut

---

## Conversation Flow

```
You open app
  → See past conversations in sidebar
  → Click "New Conversation" or just start talking/typing
  → Optional: add a topic title for this conversation
  → Eve greets you, knows your context from memory

You talk or type
  → Message sent to Lumen (localhost:1234)
  → Eve thinks and responds
  → Response spoken aloud (Kokoro TTS) + shown on screen
  → Both your message and her response saved to Supabase

You ask for information
  → "What operations are stalled?" 
  → Eve queries Supabase/Arena
  → Surfaces the answer in conversation
  → Optionally: operations panel slides in to show visual detail

You ask her to do something
  → "Create a new operation for the Amulet payment flow"
  → Eve creates it in Supabase via Arena
  → Confirms in conversation
  → You can see it immediately in the operations panel

You switch to Vera
  → "Switch to Vera"
  → Vera loads her memory, takes over
  → Same conversation thread continues
```

---

## Technical Architecture

```
Lumen Desktop App (SwiftUI native macOS)
├── Voice Layer
│   ├── Microphone input (AVFoundation)
│   ├── Speech recognition (Whisper or Apple Speech)
│   └── TTS output (Kokoro local or AVSpeechSynthesizer)
│
├── Brain Layer
│   ├── LM Studio API → http://localhost:1234/v1/chat/completions
│   ├── Model: Qwen 3.5 9B (Q4_K_M) default
│   └── System prompt: loaded from memory files
│
├── Memory Layer
│   ├── eve-base.md — always loaded for Eve
│   ├── eve-private.md — Patrick only
│   ├── vera-base.md — always loaded for Vera
│   └── vera-private.md — Patrick only
│
├── Data Layer
│   ├── Supabase client — conversations, operations, tasks, agents, humans
│   └── Arena API → http://localhost:3001 — execution and agent management
│
└── System Layer
    ├── AppleScript / Shell — open apps, control Mac
    ├── File system access — read/write files
    └── Clipboard manager
```

---

## Data Models (Supabase)

```
conversations (id, title, topic, personality, created_at, updated_at)
messages (id, conversation_id, role, content, timestamp)
operations (id, title, status, assigned_agent, created_at)
tasks (id, operation_id, title, status, due_date)
agents (id, name, type, status, directive, protocol)
humans (id, handle, display_name, role, access_level)
```

---

## Phase 1 — Build This First

Get the core loop working end to end:

1. **Persistent chat** — start conversation, talk/type, save to Supabase, reload on next open
2. **Voice in/out** — microphone → Lumen → Kokoro TTS → speaker
3. **Sidebar** — browse and open past conversations
4. **Basic operations panel** — list operations from Supabase, create new ones
5. **Lumen status** — show if localhost:1234 is reachable, what model is loaded

Do not build: agent creation, system control, Vault browser, Humans panel. Those are Phase 2.

---

## Phase 2

6. Agent management (create, assign, monitor)
7. Task management with ClickUp sync
8. System control (open apps, files, clipboard)
9. Vault browser (Obsidian + memory files)
10. Humans panel

## Phase 3

11. Vera personality + switching
12. Full screen focus mode
13. Animated panel system
14. Nexus map
15. Arena deep integration (Amulet, payments, protocols)

---

## Rules

- **Offline first** — Lumen (localhost:1234) is the brain. Cloud is optional and explicit
- **Nothing is lost** — every conversation saves to Supabase immediately
- **Eve/Vera are brains, not agents** — they think and speak, Arena agents execute
- **Private memory is sacred** — eve-private.md and vera-private.md never leave the local machine, never sync to Supabase
- **Voice and text are equal** — never feel like the app is "voice only" or "text only"
- **Native macOS** — no Electron, no web views, pure SwiftUI

---

*Lumen is where you think with Eve. Nexus is what gets built from those thoughts.*
