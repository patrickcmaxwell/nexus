# nexus-web Polish & Mobile Pass — 2026-05-06 / 2026-05-07

**Status:** ✅ Shipped to production. Multiple incremental deploys.
**Trigger:** Patrick said "Lots of broken parts and mobile issues" → triage + fix sweep.

This document catalogs the recent rapid-fire improvements to nexus-web so the next session knows what changed and why.

---

## Categorized changes

### Mobile layout fixes

The recurring root cause was **stacked horizontal padding** on small viewports — outer container padding + inner card padding + element padding all compounded, leaving message bubbles / forms with way less effective width than the screen had.

| File | Fix |
|---|---|
| `components/dashboard/MaxwellClient.tsx` | Reduced 3 layers of horizontal padding (`px-3` → `px-2` on mobile), widened user message bubbles (`max-w-[85%]` → `max-w-[92%]`), shrunk header button padding, tightened gaps. Touch targets bumped: send/voice/topic buttons `w-9 h-9` → `w-11 h-11` on mobile (was below iOS 44pt minimum). |
| `components/dashboard/SettingsClient.tsx` | Top padding `p-6` → `p-4 sm:p-6 md:p-10`. Identity card avatar+form was `flex items-start gap-5` with no wrap → now stacks vertically on mobile with avatar centered. Sessions list rows stack info-above-button on mobile so Revoke isn't crushed. |
| `components/dashboard/ConsoleClient.tsx` | Tab nav was `flex flex-wrap` (4 tabs awkwardly wrapped). Now `overflow-x-auto` with `whitespace-nowrap` per tab — feels native, no layout jump. Page padding tightened. |
| `app/dashboard/agents/page.tsx` | Hero core `w-64 h-64` was eating 90% of viewport on phones → `w-44 h-44 sm:w-56 md:w-80`. Agent name + role got `truncate` + `min-w-0` chain so long names stop pushing the status dropdown off-screen. |
| `app/dashboard/humans/page.tsx` | Invite form face preview `w-32 h-32` → `w-24 md:w-32`. Tightened gap on mobile. |
| `app/dashboard/suits/page.tsx` (now real data — see below) | Mobile padding + grid responsive |
| `app/dashboard/systems/page.tsx` | Subsystems grid `grid-cols-2` → `grid-cols-1 sm:grid-cols-2`. Padding tightened. |
| `components/dashboard/MissionsClient.tsx` | Form `grid-cols-2` → `grid-cols-1 sm:grid-cols-2` (was crammed at phone widths) |
| `components/dashboard/ArenaPanel.tsx` | Stat tile gap shrunk on mobile |

### Maxwell chat error handling

| Issue | Fix |
|---|---|
| `handleDeleteConversation` did optimistic UI removal even if API failed → orphan UX | Now checks `res.ok`, alerts on failure, doesn't mutate state |
| `submitMessage` silently dropped user's typed text on `/api/eve/conversations` POST failure | Restores text into input box + alerts user. Network blip doesn't lose work. |
| Tool-call cards rendered with success-color border even on FAILED | Border now flips rose-tinted on `!success` so the failure signal matches the FAILED badge |

### Suits page — wired to real data

**Before:** Hardcoded array of Tony Stark suits (Mark III, Mark VII, Hulkbuster, etc) with fake POWER/ARMOR/SPEED bars. Looked impressive, was 100% fiction.

**After:** Reads from the real `agents` table for the active human. Same HUD aesthetic, real data:
- Each card shows agent name + role + status pill (active/standby/offline)
- Capability chips (the agent's `capabilities` array)
- Click to expand: personality core + primary directives
- "EDIT IN AGENTS BAY →" link to /dashboard/agents
- Empty state: "NO SUITS DEPLOYED" → CTA to build one

**Files:**
- `app/dashboard/suits/page.tsx` — RSC that fetches agents
- `components/dashboard/SuitsClient.tsx` — new interactive client component
- The PREVIEW banner I added previously is gone — it's no longer fake.

### Systems page — preview banner

Still hardcoded fake telemetry (arc reactor, repulsor array, etc). Patrick called it out as broken; rather than delete the visual (he likes the Iron Man HUD theming), I added a `[PREVIEW]` honesty card explaining it'll become real Nexus stack telemetry (function p95s, Arena failures, Supabase health). Visitors no longer mistake fake data for real status.

### Auth page copy

`/auth/face` footer claimed "FACE SCAN ENABLED · CANNOT BE BYPASSED" but the code actually allowed skipping face enrollment if the upload failed. Updated to "FACE SCAN ENABLED · STRONGLY RECOMMENDED FOR INSTANT LOGIN" — accurate.

### Lumen face login server-side fix (CRITICAL)

The native face-capture in Lumen was hitting `/api/security/face/match` and getting back opaque 500s. Lumen showed "SERVER ERROR" with no detail.

**Root cause:** `@vladmandic/face-api`'s package.json points `main` at `face-api.node.js` which hard-requires `@tensorflow/tfjs-node` (30MB native binary, blows Vercel's 250MB cap, AND pnpm strict isolation hides it from face-api). The `module`/`browser` field points at `face-api.esm.js` which bundles webgl backend → crashes Node init with `TypeError: this.util.TextEncoder is not a constructor`.

**Fix:** Imported `@vladmandic/face-api/dist/face-api.node-wasm.js` directly. Added `@tensorflow/tfjs-backend-wasm` dep. WASM gives ~150-300ms inference, no native binaries, fits Vercel.

**Files:**
- `app/api/security/face/match/route.ts` — explicit node-wasm path import + wasm backend setup
- `package.json` — added `@tensorflow/tfjs-backend-wasm`
- Wrapped both `loadFaceApi()` and inference in try/catch with detail in JSON response so future failures are diagnosable from Lumen.

**Memory updated** at `/Users/shadow/.claude/projects/-Users-shadow-code/memory/feedback_vercel_native_deps.md` with the exact incantation so this doesn't bite again.

---

## Files touched (this arc)

```
app/dashboard/suits/page.tsx                       ← rewrite to RSC + real agents
app/dashboard/systems/page.tsx                     ← preview banner + mobile
app/dashboard/agents/page.tsx                      ← mobile (hero + truncate)
app/dashboard/humans/page.tsx                      ← mobile (invite form)
app/dashboard/operations/page.tsx                  ← (audit only — no change yet)
app/auth/face/page.tsx                             ← honest footer copy
app/api/security/face/match/route.ts               ← face-api wasm fix + error visibility
components/dashboard/MaxwellClient.tsx             ← mobile width fixes + error handling
components/dashboard/SettingsClient.tsx            ← mobile layout
components/dashboard/ConsoleClient.tsx             ← mobile tabs
components/dashboard/EveMessage.tsx                ← failed tool-card border
components/dashboard/MissionsClient.tsx            ← form grid mobile
components/dashboard/ArenaPanel.tsx                ← stat grid mobile
components/dashboard/SuitsClient.tsx               ← NEW
package.json + lockfile                            ← +@tensorflow/tfjs-backend-wasm
```

## What's still on the deferred list

- **Owner self-recovery** — `/api/admin/reset-credentials` blocks owners from resetting their own creds. Needs the recovery-codes flow (decision N2 in `/code/echo/decisions.md`).
- **Console missing tabs** — Lumen Console has 6 tabs; nexus-web Console has 4 (no Search, no Status). Feature work.
- **Operations page mobile** — flagged as Severity 1 in audit but works (just awkward). Lower priority.
- **EndpointsHealth POST/PATCH/DELETE probes** — return "not implemented." Either build or hide non-GET verbs.
- **Search palette mobile** — Cmd-K palette never tested on mobile (mobile users wouldn't have Cmd key anyway; needs alternate trigger).

## Test plan

After Patrick's deploy + DNS work:

1. Open nexus-web on phone: `/dashboard/maxwell` chat should feel breathable, not bunched
2. `/dashboard/settings` on phone: avatar centered, sessions revoke button visible
3. `/dashboard/console` on phone: tabs scroll horizontally
4. `/dashboard/suits`: shows real agents (Eve, Vera, Blitz, etc), not Mark III
5. `/dashboard/agents` on phone: hero core no longer fills viewport
6. Lumen: tap FACE → sign in (no more SERVER ERROR)
7. Eve chat: ask "is anything broken in Arena?" → calls `arena_failures` tool
8. Eve chat: ask "what providers can I use?" → calls `arena_providers` tool
