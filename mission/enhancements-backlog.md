# Enhancements Backlog

**Created:** 2026-05-04
**Source:** Director-curated wishlist after the multi-wave Lumen rebuild.
**Use:** Pull from here when picking the next pass. Items are scoped (S/M/L) and grouped by what they unlock. ★ = my read on highest impact per hour spent.

---

## Eve chat experience

- [x] **★ Tool-call visualization cards** *(M)* — `/api/eve` now returns `tool_calls: [{name, args, result}]` for every tool fired. Lumen renders each as a colored card (icon + tool family color + headline + detail + ✓/FAILED state) above Eve's prose, plus a "N ACTIONS" pill in the message header. nexus-web/iOS just need a renderer to consume the same field.
- [ ] **★ Streaming for Grok replies** *(M)* — local already streams, Grok currently waits-then-dumps. Add SSE on `/api/eve` + Lumen consumes deltas. Makes Eve feel 10× faster.
- [x] **Markdown + code-block rendering** *(S)* — `MentionRenderer.attributedRich` parses `**bold**` / `*italic*` / inline `code` / lists, plus fenced code blocks render as `CodeBlockView` with copy button.
- [x] **Edit & regenerate last prompt** *(S)* — hover any user message → pencil icon → inline edit → Enter (or up-arrow button) re-submits. `LumenStore.regenerate(fromUserMessageId:newText:)` truncates to that turn and re-sends.
- [x] **Conversation search** *(M)* — ⌘F (or SEARCH button in thread header) opens a search bar. Live highlighting + counter ("3 of 12") + ↑/↓ to cycle + auto-scroll-to-current. ESC closes. Suppresses auto-scroll-to-bottom while active. Currently scoped to the live thread; cross-thread search is a next pass.
- [x] **Per-message TTS** *(S)* — hover any message → 🔊 button reads it. Right-click → "Read Aloud" / "Stop Speaking". Works in main thread and ConversationWindow pop-outs.
- [x] **Multi-select messages** *(M)* — ⌘-click any message to toggle selection. Floating action bar at bottom shows count + READ ALOUD (chronological order) + COPY + STOP + clear-×. Selected messages get a left accent bar + tinted background.

## Ambient + real-time signal

- [x] **★ macOS notifications** *(S)* — `LumenStore.diffAndNotify()` posts via UNUserNotificationCenter when an agent's `total_findings` ticks up or an operation's status changes between polls. Permission is requested lazily on first dashboard refresh.
- [x] **Dock icon badge** *(S)* — `LumenStore.refreshDockBadge()` sets `NSApp.dockTile.badgeLabel` to the count of active operations + active agents. Updates after every dashboard refresh.
- [ ] **System-wide hotkey for Quick Capture** *(M)* — currently ⌘⌥N only works when Lumen is focused. Use `MASShortcut` (or Carbon) to grab it globally.
- [x] **Live "what changed since last visit" stripe in briefing** *(M)* — `/api/eve/briefing?since=<ISO>` endpoint returns delta + stats. Lumen `EveBriefingView` shows a "WHAT CHANGED SINCE LAST VISIT" section at the top with counter pills (NEW OPS / STATUS Δ / NEW RECORDS / FINDINGS / RESEARCH ✓) plus an inline list of the top items. Auto-fetched on view appear; tracks last-fetched timestamp via `@AppStorage` so each visit shows only what's new since the prior one.

## Capture & input

- [ ] **★ Smart paste** *(M)* — paste image/URL/long text → Eve auto-classifies (intel / task / memory / note) and offers to file it.
- [ ] **Voice memo capture** *(M)* — longer-form recording (not commands), Whisper transcribe, store as record/memory.
- [ ] **Drag-drop file → analyze** *(L)* — drop PDF/doc onto Lumen, server extracts + summarizes + Eve offers to file. Needs server-side parsing.

## Knowledge view

- [ ] **Map time-scrubber** *(M)* — slider above the Nexus Map shows nodes fading in by date. See how the system evolved.
- [ ] **Group view** *(M)* — pick a group, see all members + shared ops/agents/memories in one panel.

## System / dev

- [ ] **Performance dashboard** *(M)* — token usage, p50/p95 latency per route, cost per Eve turn, brain distribution. Right-side opt-in panel.
- [ ] **Offline mode — Layer 1 credential cache** *(L)* — already specced in `mission/offline-mode.md`. Lumen opens without internet via cached PIN/face. Real architecture work.

## Auth / identity

- [ ] **Song-snippet auth factor** *(M)* — Director seeds (2026-05-05):
  > "a tone like a dial tone on a phone played in a sequence."
  > "if someone knows the tone of a few notes from a song can access everything."

  The secret is a melody. The user picks a few notes from a song they know — first phrase of a favorite tune, a riff, a jingle — and reproduces it (tap the tones on an on-screen keyboard, or hum into the mic) to authenticate. Songs are the most universal human memory device, so this trades short-and-fragile (4 digits = 10k combos) for memorable-and-strong (7 notes × 24 semitones = ~4.6B combos before rhythm).

  **Implementation sketch:**
  - On-screen keyboard plays each key's tone on tap (DTMF or piano), records the sequence.
  - Optional mic input for hum-it mode (pitch-detect + quantize to nearest semitone, normalize tempo).
  - Store a hash of `(pitch_class, relative_duration)` tuples — pitch-shifted humming still matches because the melody is keyed on intervals, not absolute frequency.
  - Optional fuzzy-match tolerance on rhythm (slow vs fast hum of same melody → same hash).

  **Open design choices when picking this up:**
  - Replace PIN entirely, OR run alongside as a third factor (face / PIN / song)
  - Single fixed melody per user, or a dictionary of accepted melodies that all unlock?
  - Is the on-screen keyboard required, or can the user pick from a song search ("Mary Had a Little Lamb") and auto-derive the hash?

## Persona / workflow

- [ ] **Vera surface** *(M)* — admin chat distinct from Eve. System maintenance, log review, schedule. Specced in `mission/operation-letsgo.md`.
- [x] **Saved prompt templates** *(S)* — five built-in templates wired through the slash-command popup: `/standup`, `/review`, `/dump`, `/morning`, `/eod`. Selecting one inserts the template body into the input. Library extensible via `TemplateLibrary.templates`.
- [ ] **Custom Eve modes** *(M)* — Research / Focus / Weekend mode toggles tone + which tools she'll fire.

## Detail-card density (cont'd)

- [ ] **Memory detail upgrade** *(S)* — last-referenced timestamp, related operations, source breakdown.
- [x] **Directive detail upgrade** *(S)* — 4 metric tiles (STATE / PRIORITY / TARGET / INFLUENCE) plus an at-a-glance bar showing siblings-of-type and total active count. Inline content rendering kept.

---

## Sequencing recommendation

Most likely order if working through this list:

```
Pass 1 — Eve chat polish (visible, mostly Lumen-side)
  ├─ Markdown rendering           [S]
  ├─ Edit & regenerate            [S]
  └─ Conversation search          [M]

Pass 2 — Eve speed + visibility (server + client)
  ├─ Streaming Grok               [M]   (server SSE + client consumer)
  └─ Tool-call viz cards          [M]   (server tool_calls field + client renderer)

Pass 3 — Ambient signal
  ├─ macOS notifications          [S]
  ├─ Dock icon badge              [S]
  └─ "What changed since" stripe  [M]   (new /api/eve/briefing endpoint)

Pass 4 — Capture
  ├─ Smart paste                  [M]
  ├─ System-wide Quick Capture    [M]
  └─ Voice memo capture           [M]

Pass 5 — Knowledge view + persona
  ├─ Map time-scrubber            [M]
  ├─ Group view                   [M]
  ├─ Vera surface                 [M]
  └─ Custom Eve modes             [M]

Pass 6 — Foundations
  └─ Offline mode Layer 1         [L]
```

Update this file as items land. When something gets built, move its checkbox to `[x]` and link to the commit/journal entry.

---

## Recent landings (2026-05-16 → 2026-05-18)

Items that shipped this push but didn't have explicit checkboxes here:

- [x] **★ Push notification pipeline (server + iOS)** — APNs HTTP/2 + JWT signing, device registry, dispatch hooked into agent/schedule/research/terminal events. iOS `NexusPushClient` + `@UIApplicationDelegateAdaptor`. Settings UI with "Send test push." See `lib/push/dispatch.ts`, `/api/push/*`, journal 2026-05-16.
- [x] **★ Eve terminal watcher v1** — minute cron classifies snapshots for blocker/confirm/done/idle and dispatches alerts. See `lib/terminal/classify.ts`, `/api/cron/terminal-watcher`, journal 2026-05-16.
- [x] **Self-service face photo upload** — `FacePhotoUploadModal` in Settings. Extracts descriptor client-side, appends to enrolled set, optional avatar update in same flow.
- [x] **Self-service forgot-PIN flow** — `/auth/forgot` + email reset link via `lib/email/sendPinReset.ts`.
- [x] **Admin user lifecycle complete loop** — unlock, clear-face, resend-invite (non-destructive), rotate-and-resend, delete-human (type-name confirm). All surfaced in humans list + detail.
- [x] **iOS double-message bug fix** — re-entrancy guard + UUID-based bubble tracking in `EveVoiceManager`.
- [x] **nexus-web composer responsiveness (round 1)** — `MaxwellClient` + `EveCommand` collapse cleanly under 640px.

## Outstanding follow-ups (next pass candidates)

- **Path B — local memory recall** — embed `eve_memory` rows, route recall queries through cosine-similarity before falling back to Grok. Patrick's pick before session close. Genuinely eliminates API spend for recall.
- **Path A — server-side memory distillation** — daily grok-3-mini job over recent conversations to propose memories. Pairs with Path B.
- **Terminal watcher LLM upgrade (v2)** — feed snapshots to grok-3-mini for "alert? y/n + reason" classification. Catches off-script behavior the regex can't.
- **APN cert envs on Vercel** — Patrick still needs to set `APNS_TEAM_ID`/`APNS_KEY_ID`/`APNS_KEY_PEM`/`APNS_TOPIC` before push actually delivers.
- **Composer responsiveness round 2** — verify iPad portrait + iPhone SE; audit the remaining chat surfaces called out in the "audit all chat surfaces" memory note.
