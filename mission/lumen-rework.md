# Lumen Rework — Director's UX requests (2026-05-04)

**Created:** 2026-05-04
**Source:** Director's after-build feedback once /Applications/Lumen.app was running outside Xcode.
**Goal:** Make Lumen genuinely usable for daily work. Today's symptoms: dashboard feels empty, conversation list lacks previews, pop-out broken in this build, Nexus Map unreadable.

---

## Five requests

### 1. Pop-out windows broken
**Symptom:** "cannot open live chat or conversation with eve as a new window in that build"
**Expected:** Right-click a conversation row → "Open in New Window" (worked in earlier waves per `PROJECT-STATUS.md`). Live thread should also have a "POP OUT" button per state notes.
**Likely cause:** Regression in `lumen_desktopApp.swift` `WindowGroup(id: "conversation-detail")` scene, OR `ConversationWindow.swift` reference, OR `openWindow(id: "conversation-detail", value: convId)` call sites lost a parameter type. Needs diagnosis.

### 2. Conversation list lacks previews
**Symptom:** "viewing past conversations in the list you only see actions no chat history or key points from the convo"
**Expected:** Each row shows last assistant line (220 chars) + message count. The API already returns this — `/api/eve/conversations?withPreviews=1` adds `preview` and `message_count` fields. Lumen's `ChatRow2` should render them.
**Fix:** Bind the existing API fields into the existing row component. Probably 30 min if just unwired; more if API call doesn't pass the param.

### 3. Eve dashboard briefing
**Symptom:** "Where is an intro cool interface where eve comes up in a dashboard view and gives an update of what is going on"
**Expected:** When you launch Lumen (or hit Home), Eve greets you with:
  - What changed since last session (new operations, agent findings, completed research)
  - Outstanding directives / things needing attention
  - Option to **continue current convo** OR **end current + start new thread**
**Why it matters:** Director wants Lumen to feel like a *briefing console*, not a chat client.
**Build path:** New `EveBriefingView` that calls something like `/api/eve/briefing` (new endpoint that aggregates recent agent activity + open ops + last conv summary), renders as cards. Conversation continuation is a SwiftUI control that wires to existing `LumenStore.send()` vs `LumenStore.newConversation()`.

### 4. More data in the views
**Symptom:** "more usable desktop app and more data in the views"
**Examples observed:** Op detail cards, agent cards, group panels — all could carry more density. Currently they're spec'd for "clean" but Director reads as "empty."
**Build path:** Pass over each detail card, add stats/metadata that the API already returns but UI hides:
  - Op detail: total findings, last scan, agent assignments, briefs count, related ops
  - Agent detail: total findings, recent activity (already there), avg scan time, status distribution
  - Conversation detail: turn count, source, model used, durations
  - Memory bank: type counts, last updated, related operations
  - Directive: when last referenced by Eve

### 5. Nexus Map redesign — 2D primary mode
**Symptom:** "3d thing you can't read titles and see where things connect"
**Expected:**
  - **Default to 2D pan/zoom map** with readable labels, visible cluster boundaries, and edge lines that show how items connect.
  - Tap a node → not a tiny popup; a side-panel or overlay with **full overview** (title, type, summary, related items, link to the entity's detail panel).
  - Keep 3D as a secondary mode (`MAP MODE: 2D | 3D` toggle) for when the user wants the universe-vibes view.
**Build path:**
  - New `NexusMap2DView` using SwiftUI Canvas + drag/zoom gestures. Force-directed layout (or pre-computed clusters per type).
  - Refactor existing `NexusMapView.swift` (576 lines, currently SceneKit-only) so the toggle can swap views.
  - Selected-node side panel replaces the current tiny popup.

---

## Suggested execution order (priority + payoff)

| # | Item | Effort | Director payoff | Notes |
|---|---|---|---|---|
| **1** | Conversation previews wired to UI | 30 min | High | API already returns the data |
| **2** | Pop-out windows debug + fix | 30-90 min | High | Regression from a recent wave |
| **3** | 2D Nexus Map view + toggle | 2-3 hr | Highest | Director's biggest pain point |
| **4** | Selected-node side panel (replaces popup) | 1 hr | High | Pairs with 2D mode |
| **5** | Eve dashboard briefing | 2-3 hr | High | New endpoint + new view |
| **6** | Data density pass across detail cards | 1-2 hr | Medium | Incremental, can be parallel |

**Recommended first cut (one Lumen rebuild):** items 1 + 2 + 3 + 4 — restores pop-out, lights up the conversation list, replaces the unreadable 3D map with a usable 2D one. ~4 hours. Briefing view + density pass become the next session.

---

## Cross-cutting notes

- **Xcode is open** during edits — Director must save (Cmd+S) before I write any Swift files, otherwise Xcode's editor buffer wins on autosave.
- **Build script:** after Swift edits, `./scripts/build-lumen.sh` produces a fresh `/Applications/Lumen.app` (Lumen must be quit to install — script will remove the previous copy first).
- **Re-launch flow:** quit → relaunch from Spotlight. The current Xcode-attached debug build and the standalone Release build coexist.
- **No backend changes required for items 1, 2, 5 mostly** — endpoints exist (conversations preview, dashboard overview, agent activity, operation records). Item 3/Eve briefing endpoint is the only new server-side work.

---

## Status

### First cut (this session) — SHIPPED in /Applications/Lumen.app
- [x] **#1** — Server: `message_count` + `preview` accurate for all 265 conversations (PostgREST row-cap bug fixed via per-conversation queries).
- [x] **#2** — Pop-out windows promoted: toolbar items moved from `.secondaryAction` to `.primaryAction`; new always-visible thread header bar above the live chat with explicit POP OUT / END & NEW / NEW buttons.
- [x] **#3** — 2D Nexus Map (default) + 2D/3D toggle in HUD. Pan, pinch-zoom, ±/reset buttons. `@AppStorage` persists choice.
- [x] **#4** — Selected-node side panel (420pt, full height) with full preview, tags, **CONNECTIONS list** (click any connection → jumps to that node), OPEN IN DETAIL WINDOW.
- [x] **#5 (partial)** — `EveBriefingView` replaces the bland empty state when there's no active thread. Shows: time-aware greeting, stats row (5 metrics), directives needing attention, last-conversation card with **CONTINUE THIS THREAD / START FRESH** buttons, active operations preview, 5 quick-prompt chips that send to Eve directly.

### Next session
- [ ] **#5b** — Eve briefing: server endpoint `/api/eve/briefing` for "what changed since last session" timeline (recent agent findings, new operation_records, completed research). Currently the view is built from existing static store data — works but doesn't show *what's new since last visit*.
- [ ] **#6** — Detail-card data density pass: Operation detail (findings count, last scan, agent assignments, briefs count, related ops), Agent detail (avg scan time, status distribution), Memory detail (last referenced, related ops), Directive detail (last invoked).
- [ ] Right-click context menu on conversation rows in **non-split** layout (currently only split layout has it).

Cross-link to `journal.md` when each lands. Update `PROJECT-STATUS.md` with the new map UX.
