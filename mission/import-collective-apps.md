# Import Collective: External App Code → Nexus

**Created:** 2026-05-04
**Source projects reviewed:** IRIS-AI, OpenJarvis, Jarvis-Desktop-Voice-Assistant (all under `/Users/shadow/code/`)
**Goal:** Pull high-value capabilities into Nexus without disrupting current operations.

---

## TL;DR scoring

| Project | License | Verdict | Why |
|---|---|---|---|
| **IRIS-AI** | MIT | **High value, direct ports** | Electron + TS — same stack as `nexus/desktop/`. Net-new capabilities (OCR, hotkey overlays, window mgmt) fill known Nexus gaps. |
| **OpenJarvis** | Apache 2.0 | **High value, pattern lifts** | Don't port the agent stack (overlaps Eve). Take the registry/event-bus/Rust-security/MCP-adapter scaffolding. |
| **Jarvis-Desktop-Voice-Assistant** | MIT | **Mostly skip** | Single-file Python script, Windows-hardcoded, blocking STT. Nexus already exceeds it. Borrow greeting concept only. |

---

## Nexus current state (relevant gaps)

From `PROJECT-STATUS.md` and surface survey:

| Capability | Status |
|---|---|
| Voice STT/TTS | ✅ complete (SFSpeechRecognizer, Web Speech API, ElevenLabs) |
| Model routing (Ollama → Grok → Claude) | ✅ complete |
| Agents, directives, RLS, threading, Nexus Map | ✅ complete |
| **Wake word detection** | ❌ absent |
| **OCR / screen capture** | ❌ absent |
| **Global system hotkeys** | ⚠️ in-app only (Lumen ⌘⌥); no system-wide |
| **MCP integrations** | ❌ absent |
| **Semantic RAG over memory** | ⚠️ partial — context injection only, no retrieval |
| **Plugin architecture** | ❌ absent |
| **Real Arena integrations (ClickUp/Stripe/Bank)** | ❌ stubbed |

---

## Integration plan (ordered low → high risk)

### Phase 1 — Net-new, additive (low risk)

#### 1.1 IRIS Screen Peeler → `nexus/desktop/` (Electron)
- **Source:** `IRIS-AI/src/main/handlers/ScreenPeeler-handler.ts`
- **What:** Hotkey-triggered screen-region capture → Gemini vision → text + syntax-highlighted code, returned to clipboard or floating overlay.
- **Slots into:** Nexus desktop (Electron). Lumen variant later via macOS Vision framework.
- **Carry over:** capture flow, ephemeral floating-window pattern, Prism.js highlighting, hotkey registration.
- **Hardening required (do NOT carry IRIS's choices):**
  - IRIS sets `contextIsolation: false` on overlay windows. **Do not.** Use `contextBridge` + dedicated preload.
  - Replace Gemini call with Nexus's existing routing chain (Ollama llava local → Grok vision → Claude vision).
  - Add temp-file cleanup hook on app quit/crash.
- **Acceptance:** ⌘⌥X (or chosen combo) → drag region → text appears in clipboard + ephemeral overlay. Eve gains "extract this from my screen" tool.

#### 1.2 OpenJarvis MCP adapter → `nexus-web/lib/eve/`
- **Source:** `OpenJarvis/src/openjarvis/tools/mcp_adapter.py` (`MCPClient`, `MCPToolAdapter`, `MCPToolProvider`)
- **What:** Wraps any external MCP server as a native tool callable by Eve.
- **Slots into:** Eve's tool registry alongside the existing 5 tools.
- **Why now:** Additive only. Eve gains the entire MCP ecosystem. No surface code changes.
- **Acceptance:** Add one MCP server (e.g., filesystem or git) to config → Eve can invoke its tools end-to-end.

#### 1.3 OpenJarvis Registry + EventBus → `nexus/shared/`
- **Source:** `OpenJarvis/src/openjarvis/core/registry.py`, `core/events.py`
- **What:** Decorator-based plugin discovery + thread-safe pub/sub event bus with comprehensive `EventType` enum (INFERENCE, TOOL_CALL, MEMORY, AGENT, SECURITY).
- **Slots into:** `shared/` (currently README-only). Foundation for the missing plugin system.
- **Why now:** Touches zero existing surfaces. Greenfield code in greenfield folder.
- **Acceptance:** Eve emits `INFERENCE_START`/`INFERENCE_END` events; one debug subscriber prints them. Done.

---

### Phase 2 — Surface-touching, additive (medium risk)

#### 2.1 IRIS Phantom Typer → `nexus/desktop/`
- **Source:** `IRIS-AI/src/main/handlers/PhantomControl-handler.ts`
- **What:** Global hotkey (Ctrl+Alt+Space) → inline prompt overlay → streaming Eve response → auto-paste into focused window.
- **Slots into:** Nexus desktop. Big productivity unlock.
- **Hardening:**
  - Verify no collision with Lumen's ⌘⌥ bindings.
  - **Replace plaintext clipboard fallback** (IRIS line 295 stores original clipboard content) with timeout-clear (10s).
  - Route generation through Nexus's brain chain, not Gemini.
- **Acceptance:** Anywhere on macOS → trigger → type prompt → response streams + auto-pastes.

#### 2.2 OpenJarvis hardware-aware model selection → Lumen + Electron pickers
- **Source:** `OpenJarvis/desktop/src-tauri/` (RAM-aware Qwen variant picker)
- **What:** Probe device RAM/CPU → recommend Ollama model variant (3b vs 7b vs 13b).
- **Slots into:** Lumen and Electron Ollama pickers (currently just lists `/api/tags`).
- **Acceptance:** Picker shows ✅ or ⚠️ next to each model based on local RAM headroom.

#### 2.3 IRIS encrypted vault → Bearer token storage
- **Source:** `IRIS-AI/src/main/security/Security.ts`
- **What:** Electron `safeStorage` with OS-keychain fallback for credentials.
- **Replaces:** Current Bearer token in `~/Library/Application Support/Lumen/session_cache.json` (Lumen) and Electron localStorage equivalents.
- **Acceptance:** Tokens at rest are encrypted by OS keychain. Audit `git grep` for any plaintext fallbacks.

---

### Phase 3 — Capability deepening (medium-high risk)

#### 3.1 IRIS Telekinesis (window mgmt) → Nexus desktop
- **Source:** `IRIS-AI/src/main/logic/telekinesis.ts` (uses `node-window-manager`)
- **What:** Eve can position windows: left-half, right-half, quadrants, maximize, multi-display.
- **Slots into:** New tool in Eve's tool registry, callable from any surface.
- **Risk:** macOS accessibility entitlements required. User prompt on first use.

#### 3.2 OpenJarvis Rust security crate → Arena
- **Source:** `OpenJarvis/rust/crates/openjarvis-security/`
- **What:** PII scanner, prompt-injection scanner, SSRF checker, taint tracking, audit logger.
- **Slots into:** Arena's tool-call pipeline, before any external action executes.
- **Why fits:** Arena already writes `arena_action_log`; this becomes a pre-flight gate.
- **Build:** Compile as cdylib → call from Node.js (Arena) via N-API. Defer Lumen/iOS bindings.

#### 3.3 IRIS RAG Oracle pattern → `nexus-web`
- **Source:** `IRIS-AI/src/main/services/RAG-oracle.ts` (cosineSimilarity at lines 43-52, LanceDB persistence pattern)
- **What:** Semantic search over the Obsidian memory vault + Supabase records.
- **Slots into:** New `/api/eve/recall` endpoint Eve can call as a tool, OR Eve auto-invokes before each turn.
- **Risk — highest in the plan:** This touches Eve's context-injection path, which is currently tuned. **Stage as opt-in tool first**, then graduate to auto-invoke after observation.
- **Tech choice:** Use Supabase pgvector instead of LanceDB (Nexus already on Supabase).
- **Acceptance:** Eve answers "what did we decide about the Arena audit trail last week?" by retrieving from Obsidian + memory records, not just system-prompt injection.

---

## Phase 4 — Skip / defer

| Source | Reason |
|---|---|
| Jarvis-Desktop-Voice-Assistant (entire script) | Below Nexus's current bar. Greeting hour-threshold idea (`jarvis.py:39-59`) only — bake into Eve's per-turn system prompt later. |
| OpenJarvis CLI (`src/openjarvis/cli/`) | 44 dirs of installer/preset config. Build Nexus CLI fresh. |
| OpenJarvis 37 connector modules | Cherry-pick later if needed. Don't bulk import. |
| OpenJarvis skill-overlay system | Overengineered for current scope. |
| OpenJarvis full agent stack | Overlaps Eve's brain. Inverting Python-first → Swift/TS-first is more work than reuse. |

---

## Hard "do not disrupt" list

Per `mission/state.md`, `PROJECT-STATUS.md`, and active workspace state:

1. **Lumen multi-window popping** — shipped 2026-05-04; Xcode may be live. Queue Swift edits, check `pgrep Xcode` before writing to `lumen/`.
2. **Eve voice pause-timing tuning** — don't override delays without A/B testing.
3. **Ollama → Grok → Claude fallback chain** — additive only; do not reorder.
4. **Source-based conversation threading** — web/desktop/lumen/ios threaded separately. Test before merging.
5. **Group RLS / `data_permissions`** — do not bypass.
6. **Arena `arena_action_log` audit trail** — Phase 3.2 adds *to* this, not around it.
7. **Pending uncommitted work** — see `mission/pending-changes.md`. Resolve before Phase 2+ touches the same surfaces.

---

## Open questions before Phase 1 starts

- [ ] Hotkey assignments: confirm ⌘⌥X (Screen Peeler) and ⌘⌥Space (Phantom) don't collide with Lumen or system-level macOS bindings.
- [ ] Vision routing: prefer local llava:7b first, or Grok vision first? (Cost vs latency.)
- [ ] MCP server priorities: filesystem? git? something custom? Pick first one for Phase 1.2 acceptance.
- [ ] pgvector: confirm Supabase project has the extension enabled before Phase 3.3.

---

## Status

- **Plan written:** 2026-05-04
- **Phase 1 started:** —
- **Phase 1 complete:** —
- **Phase 2 started:** —
- **Phase 3 started:** —

Update this file as phases land. Cross-link to `journal.md` for incident notes and `handoff.md` if work pauses mid-phase.
