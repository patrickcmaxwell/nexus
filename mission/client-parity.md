# Client Parity

**Created:** 2026-05-05
**Why:** Recent waves of work landed almost entirely in Lumen (macOS native). Nexus-web (the Next.js app) and the eventual iOS app should reach parity on the same chat experience and ambient signal. This doc tracks what lives where so we don't keep accidentally Lumen-first-everything.

**Principle:** every chat/UX feature should be sized as a row in this table the moment it ships in any client. Use it as a checklist before declaring a feature "done."

---

## Surfaces

| Code | Path | Tech | Owner of canonical UX |
|---|---|---|---|
| **lumen** | `lumen/lumen-desktop/` | SwiftUI macOS native | feature R&D happens here first today |
| **web** | `nexus-web/app/` | Next.js + React + Tailwind | needs to catch up; deployed via o-nexus split |
| **electron** | `desktop/` | Electron + React + Vite | parked per Director (do not propose work) |
| **ios** | `nexus-ios/` | SwiftUI iOS | early; planned to move next |
| **quick-capture** | `lumen/.../QuickCaptureWindow.swift` | floating mini-window | derives from lumen — should keep up |

---

## Chat experience matrix

Legend: ✅ shipped • 🟡 partial • ❌ missing • — n/a

| Feature | lumen | web | electron | ios | quick-capture |
|---|---|---|---|---|---|
| Bearer/cookie auth → Eve | ✅ | ✅ | parked | 🟡 | ✅ |
| Streaming local (Ollama) replies | ✅ | ✅ (`/api/eve/local`) | parked | 🟡 | ❌ |
| Streaming Grok replies | ✅ (`callNexusEveStreaming`, mutates message content + toolCalls in place) | ✅ (fetch + ReadableStream consumer with placeholder message) | — | ❌ | ❌ |
| Brain badge per reply (GROK/LOCAL/CLAUDE/VISION/OFFLINE) | ✅ | ✅ | parked | ✅ (IOSChatBubble shows brain pill + ACTIONS pill) | 🟡 |
| Mention chips render in Eve's text | ✅ | ✅ | parked | ❌ | ✅ |
| Mention autocomplete on `@` while typing | ✅ | ✅ (existing) | — | ❌ | ❌ |
| Slash command popup on `/` | ✅ | ✅ (renders above input, Enter runs top match) | — | ❌ | ❌ |
| Saved prompt templates (`/standup` etc.) | ✅ | ✅ (5 templates + 3 actions in `slashRegistry`) | — | ❌ | ❌ |
| Markdown rendering (bold/italic/lists) | ✅ | 🟡 (depends on component) | — | ❌ | ❌ |
| Fenced code-block rendering with copy | ✅ | ❌ | — | ❌ | ❌ |
| Per-message hover actions (copy/timestamp) | ✅ | 🟡 (copy ✓, no timestamp/edit) | — | ❌ | ❌ |
| Per-message TTS button + right-click | ✅ | 🟡 (button ✓, no right-click menu) | — | ❌ | ❌ |
| Multi-select messages (⌘-click + bar) | ✅ | ✅ (⌘-click toggles, floating bar with READ ALOUD/COPY/STOP) | — | ❌ | ❌ |
| Edit & regenerate previous prompt | ✅ | ✅ (hover EDIT pill on user msg → inline textarea → SAVE & REGENERATE truncates + re-submits) | — | ❌ | ❌ |
| Thread search (⌘F) | ✅ | ✅ (⌘F bar with counter + ▲/▼ + auto-scroll to current match) | — | ❌ | ❌ |
| Cross-thread search | ✅ (CHATS panel — searches title + content, SearchHitRow with inline highlight + match-type pill) | ✅ (existing sidebar search wired to upgraded `/api/eve/search`) | — | ❌ | ❌ |
| Tool-call visualization cards | ✅ | ✅ (`EveMessage.tsx` renders `toolCalls` prop with icon/color/state) | — | ✅ (`ToolCallCardiOS` view; `ToolCallSummary.from` mirrors Lumen) | ❌ |
| Eve briefing dashboard on empty state | ✅ | 🟡 (DashboardHome is the equivalent + has BriefingDeltaWidget) | — | ❌ | ❌ |
| "What changed since last visit" delta | ✅ | ✅ (`BriefingDeltaWidget` at top of DashboardHome right column) | — | ❌ | ❌ |
| Cosmic particle background | ✅ | ❌ | — | ❌ | ✅ |
| Always-visible thread header (POP OUT / END & NEW) | ✅ | 🟡 | — | ❌ | — |
| Per-conversation preview + count in list | ✅ (server fix) | 🟡 (server fix landed; client may not render) | — | ❌ | — |

## Ambient & system

| Feature | lumen | web | ios |
|---|---|---|---|
| Dock badge with active count | ✅ | — | ❌ |
| macOS notifications on findings/op-status | ✅ | — | n/a (push notifications a separate bigger lift) |
| System-wide hotkey (Quick Capture) | ❌ (in-app only) | — | n/a |
| Menu-bar item with quick status | ✅ | — | — |

## Map / Knowledge view

| Feature | lumen | web | ios |
|---|---|---|---|
| 2D Nexus Map (hex tiles, signals) | ✅ | ❌ | ❌ |
| 3D Nexus Map | ✅ | ❌ | ❌ |
| Focus mode + cycle navigation | ✅ | ❌ | ❌ |
| Auto-zoom-to-fit | ✅ | ❌ | ❌ |
| Side-panel detail with connections | ✅ | ❌ | ❌ |

## Detail card density

| Feature | lumen | web | ios |
|---|---|---|---|
| Operations detail (6 tiles + at-a-glance) | ✅ | ❌ | ❌ |
| Agents detail (4 tiles + activity bar) | ✅ | ❌ | ❌ |
| Memory detail (planned) | ❌ | ❌ | ❌ |
| Directives detail (planned) | ❌ | ❌ | ❌ |

---

## Server changes shipped (consumable by all clients)

These already exist in `nexus-web/app/api/*` and any client can adopt:

- ✅ `/api/eve/conversations` returns accurate `message_count` + `preview` per conversation (fixed PostgREST row-cap bug, per-conversation queries)
- ✅ `/api/eve/conversations` filters out test sources by default; pass `?includeTests=1` to override
- ✅ `/api/eve` returns `tool_calls: [{name, args, result}]` array describing every tool Eve fired in the turn — clients render as cards
- ✅ `/api/eve/briefing?since=<ISO>` returns `{since, now, stats, delta}` — new ops, status changes, new records, agent findings, completed research since cutoff. Defaults to last 24h. Powers Lumen's "What changed since last visit" stripe; web/iOS just need a renderer.
- ✅ `/api/eve` accepts `stream: true` body flag → SSE response with `meta` / `tool_call` / `delta` / `done` events. Lumen + web both consume. Tool cards arrive as discrete events; content streams word-by-word for typewriter effect.
- ✅ `/api/eve/search?q=…` returns conversations matching titles or content with `{conversation_id, title, source, snippet, matchType, role, created_at, updated_at}`. Title matches sort first, then most-recent. Bearer + cookie auth.
- ✅ Migration `018_eve_conversations_is_test.sql` (optional, hardens the source filter)

---

## Working principle going forward

**Whenever a feature ships in lumen, it gets a row in this matrix immediately.** We pick:
1. Whether it lands in web next, ios next, or both in parallel
2. Whether the canonical implementation is shared (server-side, API contract) or per-client UX

Server-side improvements (like tool_calls in `/api/eve`) are free for all clients — no porting needed beyond the renderer. Pure-UX improvements (cosmic particles, hex-grid map) require per-client implementation; web uses React/Tailwind, ios uses SwiftUI/UIKit.

## Suggested catch-up sequence for nexus-web

To bring the React side roughly to parity with where Lumen sits today, in priority order:

1. **Tool-call cards** — server already returns `tool_calls`; web Eve chat just needs the renderer.
2. **Brain badge** — web already knows which path served the response (default = "grok"); add the pill component.
3. **Per-message TTS** — `/api/eve/tts` already exists; web ships `Audio` element wired to a hover button.
4. **Markdown rendering** — likely already works via `react-markdown`; verify code-block styling.
5. **Hover actions (copy/edit/timestamp)** — straight React component work.
6. **Edit & regenerate** — same logic as Lumen: truncate thread + re-submit.
7. **Multi-select** — checkbox per message + floating action bar.
8. **Eve briefing dashboard** — port the section structure from `EveBriefingView.swift`.
9. **Mention chip rendering** — verify it matches Lumen's color scheme.
10. **Slash commands + templates** — port `SlashCommandRegistry` + `TemplateLibrary` to TS module.
11. **Conversation preview/count rendering** — verify list shows preview text + count badge (data already correct).
12. **Cosmic particles** — Canvas API equivalent; lower priority, polish.

Items requiring new server work:
- **Streaming Grok** — adds SSE on `/api/eve` (would benefit both Lumen and web).
- **Eve briefing endpoint** — `/api/eve/briefing` returning "what changed since last visit".

## Suggested first sequence for ios

Once the iOS app gets its own pass, the priority order is:

1. Auth gate parity (PIN + face) — `nexus-ios/NexusAPIClient.swift` already has this scaffolded
2. Eve chat with brain badge + mention chips
3. Local-brain mode (LAN to Ollama) — already partially there
4. Tool-call cards
5. Per-message TTS (already partial — voice picker shipped)
6. Quick Capture analog (modal sheet, not a window)
7. Push notifications equivalent of macOS notifications (real Apple Push setup — bigger project)
8. Conversation history with preview/count (data is already correct)

---

## Status of this doc

- **Created** with current snapshot of lumen vs the rest.
- Update **after every feature ships in any client**.
- Cross-link: `mission/enhancements-backlog.md` (the queue), `mission/lumen-rework.md` (Lumen-specific track), `mission/operation-letsgo.md` (boot system), `mission/offline-mode.md` (foundation).
