# Handoff

**For the next session that picks this up cold.**

Updated: 2026-05-07 ~10:30 AM (Patrick-time) — by Vera Locke during extended work session covering Arena standalone build, nexus-web polish + mobile, and Lumen face-login fix.

## TL;DR — read this first

- **Arena platform is live** at `https://arena-web-green.vercel.app` as a standalone Next.js app with 5 provider integrations, webhooks, audit log, and Eve self-introspection. Custom domain `arena.talkcircles.io` pending Patrick DNS — see `mission/pending-changes.md` "Arena domain bring-up" for the exact steps.
- **nexus-web mobile + chat polish shipped** — Maxwell chat width fixes, Settings/Console mobile, Suits page wired to real agents, Systems honesty banner, multiple touch-target + error-handling fixes. Full catalog in `mission/nexus-web-polish-2026-05.md`.
- **Lumen face login server-side fix** — `/api/security/face/match` was 500ing because face-api was loading the wrong entrypoint (needs `face-api.node-wasm.js` explicit import + tfjs-backend-wasm dep). Fixed and deployed. Lumen tap-FACE works now.
- **Working tree has extensive uncommitted changes** across nexus-web, arena-web, lumen, and mission docs. Patrick needs to commit + push.
- **Multi-user is shipped end-to-end** (older work, still relevant) — see `mission/operation-multi-user.md`.

## When Patrick comes back

Read in order:
1. `mission/state.md` (current snapshot — most current)
2. `mission/pending-changes.md` (top entry: "Arena domain bring-up" — what Patrick needs to do)
3. `mission/arena-platform.md` (full state of Arena: architecture, providers, what's deployed, test plan)
4. `mission/nexus-web-polish-2026-05.md` (catalog of recent UI/fix work)
5. `/code/echo/op-pickup.md` (cross-project resume primer)

## Critical things Patrick needs to do (this session's deliverable)

In order:
1. **Commit + push working tree** — extensive accumulated work. Suggested commit grouping in `mission/pending-changes.md`.
2. **DNS for `arena.talkcircles.io`** — point CNAME at Vercel (exact target shown in Vercel dashboard → arena-web → Domains → Add).
3. **Vercel: attach the domain** to arena-web project.
4. **Set `SESSION_COOKIE_DOMAIN=.talkcircles.io`** on BOTH nexus-web AND arena-web Vercel projects (both must have it).
5. **Set `RESEND_API_KEY`** on arena-web (copy from nexus-web env).
6. **Set `ARENA_BASE_URL=https://arena.talkcircles.io`** on nexus-web.
7. **Test the full Arena flow** — see `mission/arena-platform.md` "Test plan once domain is live" for the 9-step verification.

## What was shipped 2026-05-06 → 2026-05-07

### Arena platform (NEW, standalone)

- `arena-web/` standalone Next.js 16 app, deployed to its own Vercel project
- 5 providers: ClickUp, Notion, GitHub, Stripe, Slack — each in `lib/providers/{name}.ts`
- Connection management UI (add/edit/rotate/delete/test)
- Audit log via `arena_action_log` table (with `mocked: true` flag for safe-mock fallback)
- Auto health tracking — auth errors flip status to errored
- Connection-error notification email (Resend, 24h throttle, `error_notified_at` column)
- First-run guide for empty-state users
- Webhook receiver `/api/webhooks/{connectionId}/{secret}` — per-connection auto-generated secret, URL shown in edit form
- Eve introspection tools: `arena_providers`, `arena_failures`
- Schema migrations: 022 (notifications), 023 (webhook_secret)

### nexus-web polish

- Maxwell chat mobile: padding tightened, touch targets ≥44px, message bubbles wider, header decompressed, error handling on conversation create/delete, failed tool-card border now rose-tinted
- Settings + Console mobile: avatar centered on phone, sessions revoke button visible, console tabs scroll horizontally
- Agents page: hero core no longer fills 90% of mobile viewport, name truncation chain
- Humans page: invite form face preview shrunk on mobile
- Suits page: rewritten as RSC reading from real `agents` table (no more Mark III/VII fake data)
- Systems page: PREVIEW honesty banner (still fake telemetry; banner explains the plan)
- /auth/face footer copy: changed false "CANNOT BE BYPASSED" to honest "STRONGLY RECOMMENDED"

### Lumen face login server-side fix (CRITICAL)

- `/api/security/face/match` now imports `@vladmandic/face-api/dist/face-api.node-wasm.js` explicitly + `@tensorflow/tfjs-backend-wasm`. WASM backend, no native binaries. Memory updated at `feedback_vercel_native_deps.md`.

## What's still pending (rolling forward)

### Decisions Patrick needs to make (in `/code/echo/decisions.md`)
- N1 — repoint `nexus.talkcircles.io` (less critical now Arena uses `arena.talkcircles.io`)
- N2 — owner recovery model (A/B/C/D)
- N3 — PIN length policy
- N5 — promote Merlin to admin
- N6 — song-snippet auth angle
- P1-P3 — TalkCircles + Unstuck orientation

### Things Patrick needs to do
- Commit + push (above)
- Arena domain bring-up (above)
- Test live Arena once domain is live
- Rebuild + install Lumen.app (face-api fix is server-side, but Lumen itself has uncommitted improvements)
- Rebuild + install iOS app
- Send Londynn the actual invite when ready

### Things Vera can resume building once decisions are made
- Operation Keyholder Phase B (owner recovery — once N2 picked)
- Operation Keyholder Phase C (PIN-policy hardening — once N3 picked)
- Per-provider HMAC signature verification on Arena webhooks
- Connection-test cron (auto-flip status before next Eve call discovers breakage)
- Wire Systems page to real telemetry
- Mobile sweep on Operations / Humans / Groups / Directives (deferred from polish session — Patrick paused after Maxwell chat)

## Other pre-existing operations (still relevant)

1. **Operation Multi-User** (✅ shipped) — see `mission/operation-multi-user.md`
2. **Operation Keyholder** (Phase A shipped, B-G pending) — see `mission/operation-keyholder.md`
3. **Operation Letsgo** (Lumen + boot system) — active background
4. **Offline mode** — sequenced after Letsgo. See `mission/offline-mode.md`
5. **External app imports** — see `mission/import-collective-apps.md`

## How to resume

```bash
cd /Users/shadow/code/nexus
git status                         # see scope of uncommitted work
git log --oneline -10              # what's already in
cat mission/state.md               # current snapshot
cat mission/pending-changes.md     # top entry = what to do next
```

Then read the targeted docs:
- Arena work → `mission/arena-platform.md`
- nexus-web polish → `mission/nexus-web-polish-2026-05.md`
