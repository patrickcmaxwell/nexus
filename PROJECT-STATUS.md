# Nexus Project Status

**Last Updated:** May 4, 2026

---

## Local LLM Stack — How It Works (added May 3-4, 2026)

The local-brain swap from LM Studio to Ollama is live across nexus-web, Lumen Desktop, and the iOS app. Same wire format Ollama uses on Jetson, so this code ports unchanged when the robot lands.

**Daemon + models (macOS dev box):**
- Ollama 0.23.0 listening on `http://localhost:11434`
- OpenAI-compatible API at `:11434/v1/chat/completions`
- Pulled: `llama3.2:3b` (2.0 GB, default), `qwen2.5:3b` (1.9 GB)
- Add more anytime with `ollama pull <name>` — they appear in pickers automatically.

**nexus-web wiring:**
- `nexus-web/lib/llm/local.ts` — Ollama client + env overrides (`OLLAMA_BASE_URL`, `OLLAMA_MODEL`)
- `nexus-web/app/api/eve/local/route.ts` — POST endpoint mirroring `/api/eve` but routed through Ollama. Bearer/cookie auth, lean system prompt with memory bank, conversation threading. Two response modes:
  - Default JSON: `{content, conversationId, model, brain}`
  - SSE stream when `{"stream": true}` in body: `data: {"delta": "..."}` events ending with `data: {"done": true, ...}`
- `nexus-web/app/api/llm/models/route.ts` — GET returns `{online, models[], default}` for picker UIs.
- `nexus-web/proxy.ts` — added `X-Lumen-Client` and `Allow-Credentials: true` to CORS headers (was silently breaking PIN auth from non-web clients).
- Migration `016_eve_conversations_source_open.sql` — dropped the CHECK constraint on `eve_conversations.source` that was silently breaking conversation threading from any non-web source. Applied to prod DB.

**Lumen Desktop wiring (`lumen/lumen-desktop/lumen-desktop/`):**
- `LumenAPIManager.swift` — `localLLMURL` points at `:11434/v1/chat/completions`. `localModel` is now a `var` (was `let`), persisted via UserDefaults under `lumen.localModel`. New methods: `callLocalLLMStreaming(message:history:onChunk:)` (token-by-token via URLSession.bytes), `listLocalModels()`, `setLocalModel(_:)`. Fallback chain: nexus-web Eve (Grok + tools) → Ollama → Claude.
- `MainView.swift` — settings panel has a `ModelPickerSection` that auto-fetches Ollama's `/api/tags`, shows ACTIVE marker, persists tap selection. `pingLMStudio()` now probes Ollama. New panels: **Directives** (CRUD on `/api/eve/directives`) and **Memory Bank** (CRUD on `/api/eve/memory`). Sidebar wrapped in ScrollView so layout no longer overflows on shorter windows; voice card height reduced.

**Lumen UI sweep — map fix, brief button, input visibility, light-mode contrast (added May 4, 2026 — ninth wave):**

Director feedback: 3D map empty in screenshot, "Eve Brief buttons do nothing", floating chat hangs over panels, light mode unreadable, wasted top space. Each fixed concretely:

- **Nexus Map empty (was rendering nothing) — root cause + fix.** Camera was at `z = 320` while the conversation cluster (268 nodes) had radius `sqrt(268) × 14 ≈ 230` at `z = 20`. Camera was sitting *inside* the cluster, looking at empty space. Now `NexusMap3DScene.buildScene` computes actual scene bounds (min/max of all node positions), places camera at `extent × 1.6` distance and `look(at: sceneCenter)`. Cluster radius capped at 180pt and centers spread wider so types don't overlap. Node radii doubled (operations 4→8, agents 3.5→7, defaults 2.4→4.5) so they're visible at 600+ unit camera distances. Operation/agent/human/directive nodes float labels. Empty/loading state with `RETRY SYNC` button when nodes don't load.
- **Eve Briefs `GENERATE` button looked enabled but did nothing.** It was disabled-on-records-empty but rendered the same violet as enabled. Now: solid violet + white text when clickable, grey + secondary text + tooltip ("Add at least one record before generating a brief") when not. The disable state is finally visible.
- **Floating InputBar covered the bottom of every panel.** InputBar now hides whenever `activePanel` is anything other than the live thread or the Nexus Map. MainStage's bottom padding drops `140 → 24pt` correspondingly so panels claim full window height instead of leaving empty floor space. Live conversation + map keep the chat input.
- **Light-mode contrast — bulk semantic sweep.** `.primary.opacity(N)` where `N ≤ 0.55` → `.secondary` across MainView.swift + NexusMapView.swift. `.secondary` is AppKit-calibrated for both modes; the previous `0.4` form rendered as light grey on white in light mode (the screenshot bug). Section headers, timestamps, status pills, helper text now have proper contrast in either theme.
- **TopHUD repurposed + slimmed.** Decorative "NEXUS · LUMEN" middle text replaced with live stats: `AGENTS · OPS · MEM · DIR · MAP · SYNCED` (each with accent label + count, plus relative-time-since-sync). Vertical padding 16→8pt, horizontal 28→22pt. Background switched from layered gradient + opaque rectangle to `.ultraThinMaterial`. Top bar is now ~25% shorter and communicates state instead of branding.
- **Right-click on agent rows** ("Open in New Window" + Activate/Standby + Run Scan) shipped earlier this session — worth confirming it's present after rebuild. Same context-menu pattern as op rows + conversation rows.
- **`AgentWindow.swift` (new file)** — full per-agent native window opening via `openWindow(id: "agent-detail", value: agentId)`. Reuses `AgentDetailCard` (promoted from `private` to module-internal) so it stays in lockstep with the panel view. Direct comms chat, activity log, run-scan, activate.

`xcodebuild` BUILD SUCCEEDED on every step. Eight Swift files modified this wave; no new schema migrations.

**Lumen adaptive theme + readability rebuild (added May 4, 2026 — eighth wave):**

Direct response to "popout conversations you can't read anything" — the dark palette was hardcoded in too many places, fighting `.primary` text in light mode. Now genuinely adaptive.

- **`enum C` palette refactored** — `bg`, `surface`, `surfaceHi`, `hairline`, `dim` are now AppKit-dynamic colors (`NSColor(name:dynamicProvider:)`) that switch on `NSAppearance.isDark`. Accents (`eve`, `listen`, `think`, `danger`) tuned to read on either surface.
- **`BackgroundLayer` adaptive** — gradient stops, dot-matrix dot color, and atmospheric Eve glow opacity all branch on `@Environment(\.colorScheme)`. Light mode shows a soft white-blue gradient; dark mode keeps the navy-black look.
- **Surface RGB sweep** — every hardcoded `Color(red: 0.0X, green: 0.0X, blue: 0.0X)` background fill in `MainView.swift` (8 occurrences in card/sheet/launcher backgrounds) replaced with adaptive `C.surface`. Cards now look like cards in light mode instead of stuck-dark blobs.
- **Foreground sweep** — bulk-flipped 270 occurrences across MainView + NexusMapView from `.foregroundColor(.white.opacity(N))` to `.foregroundColor(.primary.opacity(N))` so text is white-on-dark and black-on-light automatically. Same for `.tint`.
- **Material chrome on the 3D map HUD** — search field, type filter chips, and selected-node card now use `.ultraThinMaterial` instead of hardcoded `Color.black.opacity(...)`, so they're translucent over either light or dark space.
- **Removed forced `.preferredColorScheme(.dark)`** — Lumen now follows the user's macOS Auto/Light/Dark setting end-to-end. Detail windows (Conversation / Agent / Operation) now read correctly in light mode (they were the worst offenders — black text on dark background).
- **`AgentWindow.swift`** — full per-agent native window mirroring `OperationWindow`. Shows persona/role/status, activity log with relative timestamps, DIRECT COMMS chat, run-scan + activate. New `WindowGroup(id: "agent-detail", for: String.self)` scene. `AgentDetailCard` promoted from `private` to module-internal so the window can reuse it.
- **Right-click → Open in New Window on agent rows** — agent rows now match operations + conversations: context menu with "Open in New Window", quick toggle, and "Run Scan".

`xcodebuild` reports BUILD SUCCEEDED. After `Cmd+R`, popout conversations should be readable on both light and dark macOS settings.

**Lumen overhaul wave (added May 4, 2026 — seventh wave):**

Direct response to Director's feedback ("chatbar overlapping, scroll cutoff, dim text, dead buttons, want multiple convos at once with a main chat going, 3D nexus map, voice cut-offs, light/dark auto").

- **3D Nexus Map (NexusMapView.swift)** — SceneKit-driven universe view of all 525 nodes / 339 edges from `/api/nexus-map`. Type-clustered (operations, agents, records, conversations, research, directives, topics, humans) with Fibonacci-distributed positions on per-cluster spheres. Edges drawn as glowing cylinders by relation type. Mouse: free orbit/pan/zoom. Click any node → selection card with Open button. Type filter chips, live search, refresh. Background star field for depth. Wired into PanelType `.nexusMap`, sidebar nav button, ⌘⌥0 shortcut, pop-out support.
- **Per-conversation windows (ConversationWindow.swift)** — every past conversation opens as its own native window (`openWindow(id: "conversation-detail", value: convId)`). Each window has its OWN send loop pinned to that conversationId, so the Director can run several threads side-by-side while the main view keeps doing other things. Right-click any conversation row → "Open in New Window".
- **Operation detail window** — user-built `OperationWindow` reuses `OpsDetailCard` for full feature parity. Right-click any op row → "Open in New Window" or quick status changes.
- **Live thread "POP OUT" button** — main `ConversationThread` header now has a button that opens the active conversation in its own window so the main view is freed up for other panels.
- **Conversation list shows previews** — `/api/eve/conversations` returns `preview` (last assistant line, 220 chars) and `message_count` per row. `ChatRow2` renders preview + count badge + source pill. No need to open a thread to see what's in it.
- **Backend auth fixes** — `/api/nexus-map`, `/api/operations/agents` migrated from cookie-only to `checkDesktopAuth` (Bearer + cookie).
- **Voice cut-off fixes (EveVoiceManager.swift)** — pause delays bumped (short 0.55→1.0s, medium 0.85→1.4s, long 1.15→1.9s), new `connectorPauseDelay` 2.4s when last word is "and / but / so / because / for / to / from / which / that / when…". `minSpeakDuration` 0.35→0.5s. Eve now waits when the Director is mid-thought instead of cutting in.
- **Eve clarifies instead of guessing** — DIRECTIVE 9b added to `/api/eve/route.ts` system prompt: "If ambiguous, ask ONE short clarifying question instead of guessing."
- **Auto color scheme** — removed `.preferredColorScheme(.dark)` from `MainView`, `AuthWebView`, `DetachedPanelWindow`. Lumen now follows the system setting; palette still designed around dark, but light mode no longer fights the user.
- **Readability sweep** — bulk-bumped 53 dim text opacities in MainView (0.18 → 0.45, 0.20 → 0.48, 0.22 → 0.50, 0.24 → 0.50, 0.25 → 0.55, 0.28 → 0.55, 0.30 → 0.58, 0.32 → 0.58, 0.35 → 0.60). Section headers, timestamps, secondary labels all readable now.
- **Chatbar overlap** — MainStage bottom padding bumped 96 → 140 so list rows scroll past the floating InputBar instead of being covered.
- **LumenSync (LumenSync.swift)** — background polling actor on a 5s tick. Refresh cadences: dashboard 20s · conversations 45s · directives + memory 90s · nexus map 120s (only if visited). On-demand kickers (`kickDashboard`, `kickConversations`, `kickDirectivesAndMemory`, `kickMap`) for after-action refreshes. Initial burst on auth start. ⌘R global "Sync now" button on TopHUD.
- **Right-click context menus** — op rows ("Open in New Window", quick status), conversation rows ("Open in New Window", "Load in Main Chat"). Sidebar nav already had context menus from the multi-window wave.
- **Mention chip parser fix** — dropped `underlineColor` (not a SwiftUI AttributedString attribute), kept `underlineStyle = .single`. Build green.

`xcodebuild` reports BUILD SUCCEEDED. Lumen ready for `Cmd+R` rebuild.

**Eve → Arena bridge + audit trail (added May 4, 2026 — sixth wave):**

The brain stack now pipes through to Arena. Eve can fire real-world side effects via tool calls, and every Arena action lands in a Supabase audit table.

- **Migration `017_arena_action_log.sql`** — new `public.arena_action_log` table (id, action, caller, payload jsonb, result jsonb, status, error_msg, created_at) with indexes on `created_at DESC` and `action`. Applied to prod DB.
- **Arena writes audit rows** — `arena/src/index.ts` `log()` now does `console.log` plus a Supabase REST POST (no new deps; uses `fetch` against `/rest/v1/arena_action_log`). New helpers: `writeActionLog`, `callerFromReq` (reads `X-Arena-Caller` header). Auto-loads `.env` via Node's `--env-file` flag (`dev` script updated).
- **Arena env scaffolded** — `arena/.env` (gitignored) carries `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ARENA_SECRET`. Default secret still warns in `/health`.
- **`/api/arena/log` endpoint** — GET with Bearer auth. Query params: `limit`, `action`, `caller`. Returns recent entries from the audit table for Lumen / iOS to render.
- **`lib/arena/client.ts`** — small `callArena(action, body, caller)` helper centralizing URL + Bearer secret + caller header. `pingArena()` health check.
- **Five Eve tools wired** in `/api/eve/route.ts`:
  - `arena_task_create` — title, description, assignee, due
  - `arena_task_update` — task_id, status, notes
  - `arena_payment_route` — amount, currency, splits, reference (system prompt forbids unauthorized firings)
  - `arena_sync_push` — user_id (defaults to Director)
  - `arena_recent` — read from arena_action_log (limit, action filter)
- **System prompt updated** — DIRECTIVE 5 extended to brief Eve on Arena tools and explicitly forbid unauthorized payments.
- **End-to-end verified by curl:**
  - Direct arena call → 200, action_log row landed with `caller="smoke-test"`
  - Eve prompted "USE arena_task_create" → tool fired → action_log row with `caller="eve"`, `task_id="MOCK-1777909687430"` matching what Eve reported back
  - Eve prompted "use arena_recent" → "Task 'Sentinel arena test' created by Eve. Task 'QA test task' created by smoke-test." (no hallucination — actual rows)
  - 15/15 QA still green

**Caveats:**
- Default `ARENA_SECRET=dev-arena-secret-change-me`; change in `arena/.env` and `nexus-web/.env.local` (`ARENA_SECRET`) before any non-dev use.
- Arena's external integrations (ClickUp, Stripe, etc.) are still mocks; the wire is in place but the actual provider calls are TODOs in `arena/src/index.ts`.
- Eve's reply may include hallucinated `@[label](task:id)` mentions for tasks she _talks_ about without firing the tool. The sixth-wave adds the path; nudging Grok to call the tool reliably will improve as we tune the system prompt.

**Electron vision + drag-drop (added May 4, 2026 — fifth wave):**

- **Electron desktop vision parity** — `useEve` hook now exposes `pendingImages`, `attachImage(file)`, `clearPendingImages()`. Send routes through `/api/eve/local` with images when any are pending. App.tsx adds: image attach button (paperclip icon), drag-and-drop zone over the input area, "Vision · N images" pill above input, and a "Ask about the image..." placeholder when images are attached. Vision-only requests allowed (empty text + images sends through llava). All three clients now have vision parity.

**Drag-drop vision, iOS voice picker, Stop button, Arena auth (added May 4, 2026 — fourth wave):**

- **Lumen drag-drop image** — drop any image (or image file URL) onto the input bar surface. `onDrop` captures it via `NSImage.tiffRepresentation` → PNG → base64 → `LumenStore.pendingImages`. Same vision flow fires.
- **iOS ElevenLabs voice picker** — Settings has a 6-voice Picker (Bella, Rachel, Domi, Elli, Antoni, Adam), persisted to `nexus.voiceId`. iOS `EveVoiceManager.fetchEveTTS` passes it through, mirroring Lumen.
- **Stop button in Lumen** — when `eveStatus == .speaking`, the input-bar submit button morphs into a red Stop icon. Tap stops AVAudioPlayer / synth and resets status to idle. Handy when Eve is rambling.
- **Arena Bearer auth** — `arena/src/index.ts` now requires `Bearer ${ARENA_SECRET}` on every route except `/health`. Default secret is `dev-arena-secret-change-me` with a warning surfaced in `/health`. Set `ARENA_SECRET` in env to lock down. Foundation for Eve→Arena tool calls down the road.

**Mention chips, vision attach, op briefs, iOS chat thread, agent chat, iOS vision (added May 4, 2026 — third wave):**

- **Lumen mention chip rendering** — Eve replies with `@[label](type:id)` tokens now render as colored, clickable inline chips per type (operations = amber, agents = green, records = orange, conversations = violet, topics = sky, memory = green, directives = violet). Tap a chip → MainView opens the relevant panel. Implemented via `MentionRenderer.attributed(_)` returning AttributedString, custom `nexus://mention/<type>/<id>` URL scheme, and `OpenURLAction` → `Notification.Name.lumenMentionTap`.
- **Lumen vision attach (drag & pick)** — InputBar has a new image attach button. Tap it → `NSOpenPanel` for images. Selected files base64-encoded into `LumenStore.pendingImages`. Visible "VISION · N images" pill above input. Sending while pending routes through `/api/eve/local` with images, auto-selecting `llava:7b`. Falls back to a friendly error message on vision failure. Pending images cleared after each send.
- **Operation briefs in Lumen** — `OpsDetailCard` has a new EVE BRIEFS section with 5 kinds (summary / actions / next-steps / themes / contradictions). Picker chips show which kinds have content. GENERATE button regenerates that brief via `/api/operations/<id>/briefs` POST (Grok-3 analyst). Briefs render markdown-ish content selectable. `briefsByOp` dict on store, `fetchBriefs(opId:)` and `regenerateBrief(opId:kind:)` methods. Briefs route updated to use `checkDesktopAuth` (was cookie-only).
- **iOS chat thread view** — `EveVoiceManager.messages: [ChatTurn]` now accumulates user+Eve turns. ContentView replaced single-line `lastReply` with a scrolling `IOSChatBubble` thread (max 320pt, auto-scrolls to bottom on new turn). `loadConversation(id:history:)` populates the thread from server history. `newConversation()` clears it.
- **Agent direct chat in Lumen** — Each agent in `AgentDetailCard` now has a DIRECT COMMS section. Type a message → POSTs `/api/agents/chat` (the route uses the agent's own `role`/`personality`/`directives` as the system prompt, so each agent feels distinct). Per-agent history persisted in `LumenStore.agentChats`. CLEAR button resets one agent's thread. Verified with curl: agent reply came back in character ("Director, my current status is standby…").
- **iOS vision picker** — ContentView has a `PhotosPicker` button (max 4 images per turn) that calls `voice.attachImage(_)`. "Talk to Eve" button auto-flips to "Ask Eve" when images are attached. Vision turn routes through `NexusAPIClient.askEveLocalWithImages(...)` → `/api/eve/local` with llava:7b. Same VISION pill UI as Lumen.

**Voice picker, iOS history, agent activity log, brain toggle, auto-summarize (added May 4, 2026 — second wave):**

- **Eve voice picker** — `/api/eve/tts` now accepts `voice_id` in the body. Lumen has a `VoicePickerSection` in System with 6 ElevenLabs voices (Bella, Rachel, Domi, Elli, Antoni, Adam). `LumenAPIManager.voiceId` is UserDefaults-backed via `setVoiceId(_:)`. Default remains Bella.
- **iOS conversation history** — `NexusAPIClient.fetchConversations()` + `fetchHistory(conversationId:)` + a `HistoryView` sheet on the iOS main screen. Tap HISTORY → list of past conversations → tap one → resume that thread (next message threads under the same conversationId server-side, last Eve line shown).

- **Eve voice now sounds human** — Lumen and iOS both POST to nexus-web `/api/eve/tts` (ElevenLabs Bella, eleven_turbo_v2_5) and play the returned MP3 via `AVAudioPlayer`. System `AVSpeechSynthesizer` is a graceful fallback when offline. New delegates: Lumen and iOS `EveVoiceManager` now also conform to `AVAudioPlayerDelegate` so completion fires properly.
- **Brain-mode toggle in Lumen** — `LumenStore.preferLocalBrain` (UserDefaults-backed). New `BrainModeToggle` UI in System panel: tap "Cloud" or "Local" to flip primary brain. When local-first is on, `send()` streams from Ollama and falls back to nexus-web Grok if Ollama is down. Default remains cloud-first.
- **Auto-summarization on local brain** — `lib/eve/summarize.ts` extracted as shared module; both `/api/eve` and `/api/eve/local` call `maybeSummarize` after each turn. Once unsummarized history hits 20, Grok-3-mini extracts durable memories into `eve_memory` automatically. Local conversations now grow Eve's memory bank the same way Grok conversations do.
- **Mention parsing on local route** — `/api/eve/local` now resolves `@[label](type:id)` tokens via `lib/mentions/context.buildMentionsBlock`, matching `/api/eve` behavior. Local model can ground references to operations, agents, records, etc.
- **Agent activity log** — new `/api/agents/activity?agent_id=…&limit=…` endpoint (Bearer auth via `checkDesktopAuth`). Lumen `LumenStore.fetchAgentActivity(id:)` + `activityByAgent` dict + `ActivityRow` view. `AgentDetailCard` now shows a live activity log with action-specific colors (scan_completed = green, finding_created = amber, scan_failed = red) and relative timestamps. Auto-fetched on agent select and after run/toggle actions.

**Streaming, Vision, Command Palette, Menu Bar, iOS LAN brain, Operations records (added May 4, 2026):**

This batch closed most of the bigger UX vision in one pass. None of it is runtime-tested (Lumen needs Xcode rebuild, iOS needs an Xcode project), but every endpoint it relies on is curl-verified.

- **Streaming chat in Lumen** — `LumenStore.send()` now uses `callLocalLLMStreaming` for the local-brain path. `ChatMessage.content` changed from `let` to `var` so deltas append in place. Status flips to `.speaking` the moment the first token arrives. Claude is the final fallback if the local stream fails.
- **Vision support on `/api/eve/local`** — POST body accepts `images: string[]` (base64, with or without data URI prefix). When images are present and no `model` is passed, the route auto-routes to `llava:7b`. Multimodal `content` array built per OpenAI spec. `llava:7b` (4.7 GB) pulled and verified — correctly identifies a 8×8 red PNG end-to-end through nexus-web.
- **Command Palette (⌘K)** — modal overlay in Lumen searches across agents, operations, directives, memories, conversations, and panels. Up/down/enter keyboard nav, ESC to close. Results jump to the relevant panel. Triggered by ⌘K menu shortcut → `NotificationCenter` → MainView. `LumenStore.commandPaletteVisible` controls visibility.
- **Menu bar item** — `MenuBarExtra("Eve", systemImage: "brain")` second scene in `LumenApp`. Popover shows: status indicator, last Eve reply, agent/op/memory/directive counts, jump buttons (open main window, new conversation, open any panel in detached window), current local model name. Always available even when the main window is hidden.
- **iOS direct-to-LAN local brain** — `NexusAPIClient.askLocalDirect(message:)` POSTs straight to a configurable Ollama URL (e.g., `http://192.168.1.50:11434/v1/chat/completions`). When `useLocalBrain` is on AND `localBrainURL` is set, the iOS app skips nexus-web entirely. Status reports "Ready · LAN" so it's visible. Settings UI has "LOCAL BRAIN (DIRECT)" section with URL + model fields.
- **Operations drilldown** — `OperationRecord` model + `recordsByOp` dict on `LumenStore`. `OpsDetailCard` now shows a Records section with inline "Add" form (title + content + type picker). `fetchRecords(opId:)` triggered on selection change.
- **Memory + Directive create UIs** — both panels got a "+ NEW" pill button that toggles an inline form. `createMemory(type:content:priority:)` and `createDirective(type:title:content:priority:target:)` on `LumenStore`.
- **Backend auth fixes** — `/api/operations/records` (GET, POST, DELETE) was cookie-only; now uses `checkDesktopAuth` (Bearer + cookie). Same fix earlier for `/api/eve/memory`.

**Multi-window pop-out (added May 4, 2026):**
- Any panel (Agents, Operations, Directives, Memory, Chats, Files, System, Settings) can be popped out into its own native macOS window. Drag to any monitor, fullscreen independently, treated as separate windows by Stage Manager / Mission Control.
- Three ways to open in a new window:
  1. **Hover** a workspace nav button → click the pop-out icon that appears on its right
  2. **Right-click** any workspace nav button → "Open in New Window"
  3. **Menu bar → Panels** or **⌘⌥1-7** keyboard shortcuts (1=Agents, 2=Ops, 3=Directives, 4=Memory, 5=Chats, 6=Files, 7=System; ⌘⇧, opens Settings)
- Implementation: `WindowGroup(id: "panel", for: MainView.PanelType.self)` scene in `lumen_desktopApp.swift` + `DetachedPanelWindow` wrapper in `MainView.swift`. PanelType is now Codable for value-based windowing.
- Each detached window has min size 720×540, default 980×720, hidden title bar. Store and Auth flow through via `.environmentObject` so all detached panels stay live-synced with the main window.

**iOS app (`nexus-ios/`):**
- `NexusAPIClient.swift` (new) — PIN auth (X-Lumen-Client flow → Bearer sessionId in UserDefaults), `askEve` (Grok), `askEveLocal` (Ollama), plus remote-control methods (`fetchAgents`, `fetchOperations`, `runAgent`, `setAgentStatus`, `setOperationStatus`).
- `EveVoiceManager.swift` — `askHomeBrain` actually does something now: routes to `NexusAPIClient`, threads conversations server-side via `source: "ios"`, speaks replies via `AVSpeechSynthesizer`. Voice phrases `use grok` / `use local` toggle the brain at runtime.
- `ContentView.swift` — PIN gate, VOICE / CONTROL tab switch, Settings sheet for base URL + logout. Control tab shows agents + operations live (15s refresh) with tap-to-toggle status and tap-to-run-scan.

**How to add a model:**
```sh
ollama pull qwen2.5:14b   # any model name
```
- Lumen settings panel auto-detects it in the picker.
- nexus-web's `/api/llm/models` lists it via the `models[]` array.
- Per-call override: pass `"model": "qwen2.5:14b"` in the request body to either `/api/eve/local` or Lumen's `callLocalLLM`.

**Known limits:**
- Tool calling not exposed on the local route — 3B models can't reliably do it. Use `/api/eve` (Grok) for tool flows.
- iOS can't reach `localhost:11434` from the phone; `/api/eve/local` is the iOS path to local inference (proxied through nexus-web on the LAN).
- Vercel still watches the wrong repo (`o-nexus`), so the new endpoints aren't live in prod yet. iOS works fully on home wifi pointed at the LAN Mac; cloud usage requires Vercel reconnect first.

---

## Currently Works

### Web App (`nexus-web/`)
- **Supabase Integration**: Connected with `agents`, `agent_activity`, `operations`, `operation_records`, `eve_conversations`, `eve_history`, `eve_memory`, `eve_directives`, `security_sessions`, `humans`, `groups`, `group_members`, `data_permissions`, and `group_messages` tables.
- **Autonomous Agent Engine**: `/api/agents/run` feeds conversation histories into `grok-3-mini` in batches of 10, extracts findings, and writes them to `operations` / `operation_records`. Fully functional locally.
- **QStash Agent Pipeline**: `/api/agents/process` — chained batch processor with QStash signature verification. In prod, `/api/agents/run` publishes to QStash and returns immediately (bypasses Vercel 60s timeout). Locally, runs synchronously as before.
- **Eve Auto-Trigger**: Eve's chat tool automatically triggers a background agent scan when an agent's status is set to `ACTIVE`.
- **Project JARVIS UI**: Agents dashboard rebuilt as a sci-fi HUD — holographic core avatars, scanner animations, chamfered clip-path cards, live telemetry stream.
- **Manual Overrides**: `Trigger Scan`, `Force Full Backscan`, and `Pause` buttons linked to Supabase.
- **Eve Web Chat**: Full agentic loop with tool calling (create agents, operations, records, nexus map nodes). Conversation history persisted to Supabase. Background memory summarization every 20 messages.
- **Eve Desktop Auth**: `/api/eve` now accepts Bearer tokens (Desktop/Lumen) in addition to cookies (Web). Checks `security_sessions` for both auth paths.
- **Humans Multi-Tenant System**: Full `humans` table with roles (`observer`, `collaborator`, `operator`, `admin`), invite links, face-recognition seed photos, and inline role editing from the dashboard.
- **Groups Ecosystem**: Create, join, leave, and manage groups. Group owners can edit name/description, view member lists, kick members, and delete groups via a management modal.
- **Group Chat**: `group_messages` table with RLS (group members only). Desktop app polls `/api/groups/[id]/messages` every 4s. Send messages via POST to same endpoint.
- **Granular Visibility Controls**: Agents and Operations support `private`, `shared`, `group`, or `public` visibility. Access enforced via `data_permissions` table and Row Level Security policies.
- **RLS Enforcement**: `012_permissions_rls.sql` — database-level isolation for operations, agents, and data_permissions based on visibility and group membership.
- **Autonomous Scheduling**: `/api/cron/agents` triggers active agents on schedule. `vercel.json` cron runs every 6 hours. Agents have configurable `scan_interval_hours` (default 12h). Falls back to direct in-process in dev (no QStash required locally).
- **Face Recognition**: `/api/security/face` updated to use `humans` table (migrated from `team_members`). Models load from `/public/models/` (local, no CDN dependency). Supports enroll + verify. `face_descriptor` column added to `humans` via migration `015`.
- **Desktop Dashboard API**: `/api/dashboard/overview` — endpoint returning directives, agents, and active operations for desktop clients, with CORS headers for `localhost:5173`.

### Lumen Desktop (`lumen/lumen-desktop/`)
- **SwiftUI native macOS app** — no Electron, no web views.
- **Auth Gate**: PIN (4-digit) + Face scan via nexus-web.
- **Eve Brain — 3-tier fallback**:
  1. **nexus-web `/api/eve`** (primary): Grok-3-mini with full memory, directives, tool calling, and Supabase persistence handled server-side. Requires `sessionCookie` (Bearer token).
  2. **LM Studio** (`localhost:1234`, `qwen3.5`): Local offline brain. 10s timeout.
  3. **Claude API** (`claude-haiku-4-5-20251001`): Final fallback when both nexus-web and LM Studio are unreachable.
- **Local Supabase persistence**: Only fires if nexus-web fallback path was used (nexus-web handles persistence itself when it's the primary brain).
- **Conversation Title Generation**: After 3 exchanges (6 messages), fires `generateTitle()` via LM Studio and patches the Supabase conversation title.
- **Memory Loading**: `loadMemoryContext()` reads `eve-base.md` and `eve-private.md` from Bundle first, then `~/Library/Application Support/Lumen/`. Appends Supabase `eve_memory` context.
- **Direct Supabase persistence**: `SupabaseClient.swift` sends messages directly to Supabase REST API when nexus-web is unavailable.
- **Conversation threading**: Every session auto-creates a conversation in Supabase on first message, threads all subsequent messages to the same ID. Persisted to UserDefaults.
- **Local session cache**: Backed up to `~/Library/Application Support/Lumen/session_cache.json` after every exchange. Loaded on startup if Supabase is unreachable.
- **Conversation sidebar (CHATS panel)**: Loads past conversations directly from Supabase. Tap to view full history.
- **NEW button**: Starts a fresh conversation thread.
- **Agents panel**: Shows real role, last scan time, and total findings from Supabase (via nexus-web `/api/dashboard/overview`, Bearer auth).
- **Operations panel**: Shows live ops from nexus-web dashboard API.
- **Voice**: SFSpeechRecognizer STT + AVSpeechSynthesizer TTS. Fluid listening mode (auto-restart after Eve speaks).

### Desktop Electron App (`desktop/`)
- **Stack**: Electron + React + Vite + Tailwind v4 on port 5173.
- **Full navigation rail**: 5 sections — EVE, OPS, AGENTS, GROUPS, DIRECTIVES.
- **Eve chat**: Calls nexus-web `/api/eve` directly via Bearer token (no Python bridge). Web Speech API for voice input. ElevenLabs TTS via `/api/eve/tts`.
- **Conversation history sidebar**: Toggle with HISTORY button. New conversation via NEW button.
- **Text selectable**: All chat messages support text selection and copy.
- **OPS section**: Fetches `/api/operations` — left list + right detail panel with status/priority color coding.
- **AGENTS section**: Fetches `/api/agents` — list + detail + Run Agent button (POST to `/api/agents/run`).
- **GROUPS section**: Group list + embedded chat panel with 4s polling.
- **DIRECTIVES section**: Fetches `/api/eve/directives` — filter by type, detail panel.
- **Connection indicator**: Polls `/api/dashboard/overview` every 15s to show NEXUS LIVE / NEXUS OFFLINE.
- **Dev boot**: Shows `loading.html` splash immediately, polls for Vite readiness, then seamlessly swaps to the live UI.
- **Run**: `cd desktop && npm run dev` (requires nexus-web running on 3000).

### iOS App (`nexus-ios/`)
- Supabase + ElevenLabs TTS + voice management. Current integration status TBD.

---

## Next Priorities

1. **Rebuild Lumen in Xcode** — pick up all Swift changes (3-tier brain, Bearer auth on dashboard, title generation, memory loading, Supabase key fix).
2. **Add QStash keys to Vercel** — `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `NEXT_PUBLIC_APP_URL` from console.upstash.com. Also add `CRON_SECRET`.
3. **Vercel deployment** — nexus-web lives in `patrickcmaxwell/nexus` repo but Vercel watches `patrickcmaxwell/o-nexus`. Reconnect Vercel project or push to o-nexus. Add `ANTHROPIC_API_KEY` to Vercel env vars.
4. **Operations Alerts** — Real-time UI toast/badge when agents surface new intel via Supabase Realtime.
5. **Nexus Map — Human Nodes** — Show humans on the map with public/shared data profiles and group affiliations.
6. **Robot / Jetson** — Nexus brain going into physical robot (Short Circuit style). Jetson Orin NX target. Ollama replacing LM Studio for on-device inference.

---

## Database Migrations Applied

| Migration | Description | Status |
|-----------|-------------|--------|
| `001_humans.sql` | `humans`, `groups`, `group_members`, `data_permissions` tables + RLS | Applied |
| `012_permissions_rls.sql` | Granular RLS policies for operations, agents, data_permissions | Applied |
| `013_agent_schedule.sql` | `scan_interval_hours` column on agents (default 12h) | Applied |
| `014_group_chat.sql` | `group_messages` table with RLS (group-member-only read/insert) | Applied |
| `015_humans_face_descriptor.sql` | `face_descriptor JSONB` column on `humans` for enrolled face data | Applied |

---

## Architecture

| Component | Port | Stack |
|-----------|------|-------|
| **nexus-web** | `localhost:3000` | Next.js 16 + Turbopack + Supabase |
| **desktop** (Electron) | `localhost:5173` | Electron + React + Vite + Tailwind v4 |
| **lumen** (macOS) | N/A | SwiftUI + nexus-web/LM Studio/Claude fallback chain |
| **Supabase** | Cloud | PostgreSQL + RLS + Service Role API |

---

## Security Notes

- **No secrets in git**: `SupabaseClient.swift` credentials are local-only. `.env.local` is gitignored.
- **Bearer auth on Eve API**: Desktop and Lumen authenticate with `Bearer <sessionId>` header. Web uses `nx_session` cookie.
- **Face descriptor stored in `humans`**: `face_descriptor` (enrolled) + `seed_face_descriptor` (admin-seeded) both checked during verification.
- **Lumen Claude API key**: Hardcoded in `LumenAPIManager.swift` — do not commit to public repo.

---

## Blockers / Known Issues

- QStash prod keys not yet added to Vercel — autonomous agent scheduling runs in dev-fallback mode in prod.
- Vercel watches wrong repo (`o-nexus` not `nexus`) — prod deployments not picking up latest nexus-web changes.
- Lumen macOS: Must rebuild in Xcode (`Cmd+R`) to pick up all Swift changes from this session.
- Lumen `SourceKit` cross-file "cannot find type" warnings — single-file analysis artifact, resolves at Xcode build time.
- `conversationId` from nexus-web Eve API may return null for desktop-sourced messages — persistence via nexus-web may not be threading correctly for desktop source.
- Face recognition requires Lumen to re-authenticate if the enrolled face was in `team_members` (old table) — first login will re-enroll into `humans.face_descriptor` automatically.

---

## Development Environment Requirements

### Editor & AI Assistant

**Required:** VS Code with Claude Code running in the integrated terminal.

### Quick Reference

| Task | Command |
|---|---|
| Launch Claude in current folder | `claude` |
| Start nexus-web | `cd nexus-web && npm run dev` |
| Start desktop app | `cd desktop && npm run dev` |
| Rebuild Lumen | Open `lumen/lumen-desktop/lumen-desktop.xcodeproj` → `Cmd+R` |

---

*Update this file every time you sit down to work.*
