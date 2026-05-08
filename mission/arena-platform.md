# Arena Platform — Current State

**Updated:** 2026-05-07
**Supersedes:** `arena-launch.md` (which described the old Express single-file design).
**Status:** ✅ Live in production at `https://arena.maxnexus.io`. DNS, custom domain, env vars all wired (2026-05-07).

---

## What Arena is now

Arena is a **standalone Next.js 16 app** (not the old Express service) deployed as its own Vercel project (`arena-web`). It is the executor that turns Eve's tool calls into real-world action through user-owned provider connections.

**Repo path:** `/Users/shadow/code/nexus/arena-web/`
**Vercel project:** `arena-web` (separate from `nexus-web`)
**Database:** shares the same Supabase project as nexus-web (`rtkzvsqulliaoizutsqz`)
**Auth:** users sign in via the same `nx_session` cookie as nexus-web. `SESSION_COOKIE_DOMAIN=.maxnexus.io` is set on both Vercel projects so cross-subdomain auth flows automatically.

## Architecture summary

```
User browser  ──cookie──►  arena-web /dashboard
                            │
Eve (nexus-web /api/eve)  ──Bearer──►  arena-web /api/{task,payment,sync}
                                        │
                                        ├──►  Supabase (audit log, connections)
                                        └──►  Provider APIs (ClickUp, Notion, GitHub, Stripe, Slack)
                                              │
Provider webhooks ─────────────────────────────►  arena-web /api/webhooks/{id}/{secret}
                                                  └──►  Supabase audit log (inbound/* prefix)
```

## Provider integrations (5 live)

Each provider lives in `arena-web/lib/providers/{name}.ts` and implements the `Provider` interface from `arena-web/lib/providers/types.ts`. Adding a new provider = one file.

| Provider | File | Methods supported | Notes |
|---|---|---|---|
| **ClickUp** | `lib/providers/clickup.ts` | createTask, updateTask, testConnection | Needs `CLICKUP_API_KEY` + list id per connection |
| **Notion** | `lib/providers/notion.ts` | createTask, updateTask, testConnection | Database id per connection; pages = "tasks" |
| **GitHub** | `lib/providers/github.ts` | createTask, updateTask, testConnection | Issues = tasks; per-repo connection |
| **Stripe** | `lib/providers/stripe.ts` | routePayment, testConnection | Test mode by default; live keys per connection |
| **Slack** | `lib/providers/slack.ts` | createTask, testConnection | Posts message to channel = "task" |

Provider methods are optional — connections only show options the provider supports.

## Connection lifecycle

1. **Add** — `/connect/{provider}` form → POST `/api/connections` → row in `arena_connections` with status='active'
2. **Use** — Eve fires a tool → executor finds the user's matching connection → calls provider API → records result
3. **Health track** — `lib/connection-health.ts` watches results. Auth errors flip status='errored' AND fire a notification email (24h throttle, `error_notified_at` column from migration 022)
4. **Edit / rotate** — `/connect/{provider}/{id}/edit` → can update label, rotate credentials (blank fields = preserve), test, see webhook URL
5. **Delete** — DELETE `/api/connections?id=X` → row removed; Eve falls back to safe-mock for that provider

## Webhooks (NEW, 2026-05-07)

Inbound events from providers land at `/api/webhooks/{connectionId}/{secret}`:

- **Per-connection secret** auto-generated on insert (column `arena_connections.webhook_secret`, migration 023). Rotates when connection is deleted+recreated.
- **URL displayed in edit form** with copy button so user can paste into provider's webhook settings.
- **Slack URL-verification challenge** handled (echoes the challenge string back).
- **Inbound events** logged to `arena_action_log` with action `inbound/{provider}/{event}` and caller='system'. Distinct from Eve's outbound calls in the audit log.
- **Per-provider HMAC signature verification** is intentionally NOT implemented yet — the path-token (`/{secret}`) provides MVP gating. Add per-provider signature checks (X-Hub-Signature-256 for GitHub, stripe-signature for Stripe, etc.) before turning Webhooks loose on production-critical flows.

## Eve self-introspection tools (in nexus-web)

Eve can answer questions about Arena state without needing the user to open the dashboard. Three new tools live in `nexus-web/app/api/eve/route.ts`:

- **`arena_providers`** — "what providers can I use?" → returns connected vs available.
- **`arena_failures`** — "did anything break?" → returns errored connections + recent failed action-log entries + `healthy: true` shortcut.
- **`arena_recent`** (existing) — "show me what you did" → audit log tail.

The 3 task/payment tools (`arena_task_create`, `arena_task_update`, `arena_payment_route`) accept an optional `provider` arg + auto-route to the user's matching connection.

## Dashboard

- **`/`** — landing page, asks user to sign in via Nexus (same passcode/face flow)
- **`/dashboard`** — user's connections + recent actions. First-run guide (3 steps) shows when `connections.length === 0 && actions.length === 0`.
- **`/connect/{provider}`** — add a new connection
- **`/connect/{provider}/{id}/edit`** — rotate credentials, update label, see webhook URL, test
- **`/api/health`** — public unauthenticated probe

## What's deployed and working

- ✅ All 5 providers
- ✅ Connection add/edit/delete/test
- ✅ Eve outbound tool routing per provider
- ✅ Audit log with caller + status + result
- ✅ Auto-flip to errored on auth failure
- ✅ Notification email on error (Resend, 24h throttle, requires `RESEND_API_KEY`)
- ✅ First-run guide
- ✅ Webhook receiver with per-connection secret + URL display
- ✅ `arena_failures` Eve tool
- ✅ `arena_providers` Eve tool

## What needs Patrick's hand

These can't happen autonomously:

| Task | Where | Impact if skipped |
|---|---|---|
| **DNS: add `arena.maxnexus.io`** | DNS provider for maxnexus.io | Must use Vercel-issued URL; cross-subdomain cookie auth doesn't work |
| **Vercel: attach `arena.maxnexus.io` to arena-web project** | Vercel dashboard → arena-web → Domains | (depends on DNS) |
| **Set `SESSION_COOKIE_DOMAIN=.maxnexus.io` on BOTH nexus-web AND arena-web** | Vercel env vars | Without this, signing into nexus-web doesn't carry to arena-web — users have to sign in twice |
| **Set `RESEND_API_KEY` on arena-web** | Vercel env vars (copy from nexus-web) | Connection error emails won't send (graceful — flips status, dashboard shows banner, but no email) |
| **Set `ARENA_BASE_URL=https://arena.maxnexus.io` on nexus-web** | Vercel env vars | Eve will keep using `https://arena.maxnexus.io` — works, just not pretty |
| **Provider API keys** | Either env vars OR per-connection in the UI | Without them, providers fall back to safe-mock mode (action logged with `mocked: true` flag) |

## Test plan once domain is live

1. Open `https://arena.maxnexus.io` → signs you in via existing nexus-web session (cookie auth)
2. Land on `/dashboard` → first-run guide appears (no connections yet)
3. Click "Connect ClickUp" → paste API key + list id → save → connection appears in list
4. Click the pencil → see the webhook URL (https://arena.maxnexus.io/api/webhooks/...)
5. Test it: POST a fake event to the webhook URL → check audit log for `inbound/clickup/X` entry
6. In nexus-web Eve chat: "create a task to test the integration" → Eve fires `arena_task_create`, real ClickUp task appears
7. Ask Eve: "is anything broken?" → calls `arena_failures` → returns `healthy: true`
8. Rotate the ClickUp key on ClickUp's side, fire another task → auth error → status flips to errored → email lands within 24h
9. Open `/dashboard` again → errored banner shows, click pencil → rotate creds → status flips back to active

## Critical files

```
arena-web/app/dashboard/page.tsx                          ← user's dashboard
arena-web/app/connect/[provider]/page.tsx                 ← add connection
arena-web/app/connect/[provider]/[id]/edit/page.tsx       ← edit / rotate / webhook URL
arena-web/app/api/connections/route.ts                    ← list/create/delete
arena-web/app/api/connections/[id]/route.ts               ← per-connection get/patch
arena-web/app/api/connections/test/route.ts               ← test before save
arena-web/app/api/task/{create,update}/route.ts           ← Eve outbound
arena-web/app/api/payment/route.ts                        ← Eve outbound
arena-web/app/api/sync/push/route.ts                      ← Eve outbound
arena-web/app/api/webhooks/[connectionId]/[secret]/route.ts ← inbound webhooks
arena-web/lib/providers/{clickup,notion,github,stripe,slack}.ts
arena-web/lib/providers/types.ts                          ← Provider interface
arena-web/lib/providers/index.ts                          ← registry
arena-web/lib/connection-health.ts                        ← auto error tracking + notify
arena-web/lib/email/sendConnectionError.ts                ← Resend integration
arena-web/lib/audit.ts                                    ← arena_action_log writer
arena-web/lib/auth/session.ts                             ← cookie auth (mirrors nexus-web)
arena-web/components/{ConnectionsList,RecentActions,FirstRunGuide}.tsx
nexus-web/app/api/eve/route.ts                            ← Eve tool definitions + execution
```

## Schema migrations applied

- **022_arena_connection_notifications** — adds `arena_connections.error_notified_at TIMESTAMPTZ` for 24h notification throttle
- **023_arena_webhook_secret** — adds `arena_connections.webhook_secret TEXT NOT NULL`, default `encode(gen_random_bytes(24), 'hex')`, backfilled on existing rows

Earlier migrations (017, 020, 021) created the original `arena_action_log` and `arena_connections` tables — pre-existing.

## Next steps after domain is live

In rough priority:

1. **Per-provider HMAC verification on webhooks** — GitHub uses X-Hub-Signature-256, Stripe uses stripe-signature, Slack uses X-Slack-Signature + timestamp, ClickUp uses X-Signature. Add per-provider signature check before logging inbound events.
2. **Webhook → Eve trigger** — when a Slack `:done:` reaction lands on an Eve-posted message, post status update back into the conversation. Closes the loop.
3. **Per-connection API key** — ClickUp/Notion/etc keys live on the connection row's `credentials` field today (per-user). Document this in the UI; right now users might assume there's a global env var.
4. **Connection-test cron** — every hour, hit `provider.testConnection()` for all active connections; auto-flip status before the user notices. Cheaper than waiting for the next Eve call to discover the breakage.
5. **Stripe live mode safeguards** — currently any Stripe key works. Consider requiring an explicit `?live=1` query param on connection-create for sk_live_ keys, with confirmation dialog. Payments are high-blast-radius.
