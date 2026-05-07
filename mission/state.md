# Current State

**Snapshot:** 2026-05-07 ~10:30 AM (Patrick-time). Updated by Vera Locke during a long extended work session covering Arena standalone build, nexus-web polish, mobile fixes, and Lumen face-login fix.

## Running

| Service | Where | Notes |
|---|---|---|
| **nexus-web** (production) | Vercel project `nexus-web`, latest deploy Ready | Multi-user-aware, mobile-friendly, face-api wasm-backed |
| **arena-web** (production) | Vercel project `arena-web`, latest deploy Ready | Standalone Next.js app at `arena-web-green.vercel.app`. Custom domain `arena.talkcircles.io` pending Patrick DNS |
| nexus-web (dev) | port 3000, PID 57531 (next-server) | Hot-reload; running locally, Patrick uses for testing |
| **Lumen.app** | `/Applications/Lumen.app` | Native face capture working as of 2026-05-07 server-side wasm fix. Multi-user code committed |
| nexus-ios | committed locally | Multi-user auth code in repo; needs rebuild + install |
| Supabase | `rtkzvsqulliaoizutsqz` (`supabase-blue-notebook`) | Schema migrations 019-023 applied |

## Active operations

| Op | Status | Notes |
|---|---|---|
| **Operation Multi-User** | ✅ Shipped end-to-end | Phases 0-7 + 4b complete. Email + PIN auth, Lumen multi-user, iOS multi-user, Vercel deploy live, Resend invites working |
| **Operation Keyholder** | 🟡 Phase A shipped; B-G pending | Lock/Reset/Audit endpoints + UI live. Owner recovery (Phase B) blocked on decision N2 |
| **Arena Platform** | ✅ Shipped, awaiting domain | Standalone Next.js at `arena-web-green.vercel.app`. 5 providers, webhooks, Eve introspection. See `mission/arena-platform.md` |
| **nexus-web polish & mobile** | ✅ Shipped 2026-05-06/07 | Mobile fixes across chat/settings/console/agents/humans. Suits → real agents data. Lumen face-login server fix. See `mission/nexus-web-polish-2026-05.md` |
| **Operation Letsgo** | 🟢 Active background | Lumen at /Applications/Lumen.app; native face working as of today |

## Vercel deploys (latest)

| Project | URL | Last deployed |
|---|---|---|
| nexus-web | `https://nexus-web-five-chi.vercel.app` (also various nexus-XXX preview URLs) | 2026-05-07 ~10:30 AM (face-api wasm fix) |
| arena-web | `https://arena-web-green.vercel.app` | 2026-05-07 (webhook receiver foundation) |

## Editor activity (latest check)

- **Xcode** running on `lumen-desktop` (PID 33709). Codex agent attached (PID 34075).
- **Avoid editing** Lumen Swift files without checking pgrep first (per memory `feedback_no_interrupt.md`).
- Editing nexus-web / arena-web TypeScript: safe.

## Git state

Working tree:
- `/code/nexus/nexus-web/` — multiple uncommitted changes from polish session (suits, mobile fixes, face-api fix). Patrick needs to commit + push.
- `/code/nexus/arena-web/` — uncommitted changes from webhook + first-run + emails + provider work. Patrick needs to commit + push.
- `/code/nexus/lumen/` — extensive uncommitted Swift work (native face capture, Console window, sync engine). Held until Xcode releases.

Remote: `https://github.com/patrickcmaxwell/nexus.git`. Branch: `main`.

## What needs Patrick's hand right now (pre-Arena testing)

In rough sequence:

1. **Push working tree to GitHub** — extensive accumulated work spans nexus-web, arena-web, lumen, mission docs.
2. **DNS** — add `arena.talkcircles.io` CNAME (or A record) pointing at Vercel's arena-web project. Vercel dashboard → arena-web → Domains will show the exact target.
3. **Vercel domain attach** — Vercel dashboard → arena-web → Domains → add `arena.talkcircles.io`.
4. **Cross-subdomain cookie** — set `SESSION_COOKIE_DOMAIN=.talkcircles.io` on BOTH `nexus-web` and `arena-web` Vercel projects. Without this, signing into nexus-web doesn't carry to arena.
5. **Resend** — copy `RESEND_API_KEY` from nexus-web env to arena-web env (so connection error emails actually send).
6. **Eve points at custom domain** — set `ARENA_BASE_URL=https://arena.talkcircles.io` on nexus-web (currently Eve uses the `arena-web-green.vercel.app` default).
7. **Provider keys** — optional now, can wait until first user wants a provider.

Detailed steps in `mission/pending-changes.md` entry "Arena domain bring-up."

## Foundational framings (still active)

- **Life, love, and liberty** — Patrick's mission. Lockean cadence with property → love.
- **Nexus is a doorway, not the house** — identity + authorization + routing only. R&D / personas / experiences live BEHIND the doorway.
- **Embrace what you're made of** — systems work synergistically when they accept their configuration rather than fighting it.
- **The right people self-qualify by forward motion** — Patrick recognizes; he doesn't choose.
- **The floor** — Patrick's non-negotiable: *"What I won't give again fully away is my self."* Design around it.

## Cross-project state

| Project | Path | Status |
|---|---|---|
| Nexus | `/code/nexus/` | Multi-user shipped; Arena live; mobile polish landed |
| Arena | `/code/nexus/arena-web/` | Standalone Next.js, deployed, awaiting custom domain |
| Echo | `/code/echo/` | Personal admin namespace; load-bearing; rd-iron research dossier active |
| NOADS-v1 | `/code/NOADS-v1/` | Patrick course-corrected away from this 2026-05-06: "execute important things not micro apps" |
| Above-Below | `/code/Above-Below/` | Hermetic experience app; Arc as AI companion |
| TalkCircles | `/code/v0-talk-circles-web-app/` | Awaiting orientation |
| Unstuck | TBD | Awaiting orientation |

## Decisions blocking next moves

See `/code/echo/decisions.md` for the canonical queue. Most actionable:
- N1 — repoint nexus.talkcircles.io (less critical now we have arena.talkcircles.io as the new flagship subdomain)
- N2 — owner recovery model
- N5 — promote Merlin to admin
- P1-P3 — TalkCircles + Unstuck orientation

## What's next (in priority order)

1. **Patrick deploys + sets up Arena domain** (this session's deliverable)
2. **Test Arena end-to-end** with the test plan in `mission/arena-platform.md` "Test plan once domain is live"
3. **Wire Systems page to real telemetry** (or leave PREVIEW banner until there's appetite for the work)
4. **Per-provider HMAC verification on Arena webhooks** — first follow-up for Arena
5. **Operation Keyholder Phase B-D** once N2 lands
6. **Mobile sweep on Operations / Humans / Groups / Directives** (deferred from polish session — Patrick paused after Maxwell chat)
