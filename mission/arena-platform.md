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

## Provider integrations (5 live; 4 with full OAuth)

Each provider has a base implementation in `arena-web/lib/providers/{name}.ts`. The 4 with OAuth also have `arena-web/lib/oauth/{name}.ts` helpers + start/callback/{data} routes + an Apple-styled `/connect/{name}` landing + `/connect/{name}/[id]/settings` page with a live data picker fetched directly from the provider.

| Provider | OAuth | Manual fallback | Live picker | Settings path |
|---|---|---|---|---|
| **ClickUp** | ✅ | ✅ `/connect/clickup/manual` | List (workspace → folder → list) | `/connect/clickup/[id]/settings` |
| **Notion** | ✅ | ✅ `/connect/notion/manual` | Database (only those shared with the integration) + property name mapping | `/connect/notion/[id]/settings` |
| **GitHub** | ✅ | ✅ `/connect/github/manual` | Repo (private repos marked 🔒) | `/connect/github/[id]/settings` |
| **Slack** | ✅ | (none) | Channel (private channels marked 🔒, requires bot to be invited) | `/connect/slack/[id]/settings` |
| **Stripe** | ❌ (intentional) | ✅ `/connect/stripe` | — | `/connect/stripe/[id]/edit` |

Stripe stays manual because payments are high-blast-radius; flipping it to OAuth is a deliberate decision (Q1 in `/code/echo/decisions.md`).

### OAuth flow shape (consistent across all 4)

1. User visits `/connect/{provider}` — page detects `{PROVIDER}_CLIENT_ID` env var. If missing, shows inline 5-6 step admin guide (no doc-hunting).
2. User clicks "Continue with {Provider}" → `/api/oauth/{provider}/start` mints a signed CSRF state cookie + redirects to provider's consent page.
3. Provider redirects back to `/api/oauth/{provider}/callback` with `code` + `state`.
4. Callback verifies state cookie, exchanges code for access token, fetches authorized identity (workspace name / username / repo list / etc.), persists/updates `arena_connections` row.
5. Redirects to `/connect/{provider}/[id]/settings?just_connected=1` — Apple-styled settings page with live data picker (fetched per-render via the provider's API), default-target selection, friendly name, webhook URL display, disconnect.

Tokens stored in `arena_connections.credentials.access_token` (Notion also stores `refresh_token`; ClickUp tokens are long-lived; GitHub OAuth Apps don't expire by default; Slack bot tokens are long-lived).

Provider lib reads `connection.credentials.access_token` first, falls back to legacy `api_key` / `token` / `bot_token` / `integration_token` for backward compatibility with manual-paste connections.

## Eve handoff for missing connections

When Eve fires `arena_task_create` and the user has NO matching provider connection, `/api/task/create` returns:

```json
{
  "success": false,
  "needs_connection": true,
  "provider": "clickup",
  "provider_name": "ClickUp",
  "connect_url": "https://arena.maxnexus.io/connect/clickup",
  "message": "You haven't connected ClickUp yet. Open ... to connect, then ask me again."
}
```

Eve's system prompt has a directive: when a tool returns `needs_connection: true`, surface the `connect_url` naturally as a clickable link instead of pretending the action worked or apologizing.

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

- ✅ All 5 providers (4 with OAuth, 1 manual)
- ✅ Connection add (OAuth or manual) / edit / delete / test
- ✅ Per-connection settings page with live data picker (lists / databases / repos / channels)
- ✅ Eve outbound tool routing per provider
- ✅ Eve handoff: missing-connection responses include `connect_url` so Eve can direct the user to sign in
- ✅ Audit log with caller + status + result
- ✅ Auto-flip to errored on auth failure
- ✅ Notification email on error (Resend, 24h throttle, requires `RESEND_API_KEY`)
- ✅ First-run guide
- ✅ Webhook receiver with per-connection secret + URL display
- ✅ Apple/Linear-style design across the whole platform
- ✅ Cross-subdomain cookie auth (`SESSION_COOKIE_DOMAIN=.maxnexus.io` on both Vercel projects)
- ✅ Eve introspection tools: `arena_providers`, `arena_failures`

## What needs Patrick's hand

To activate any provider:

1. Register OAuth app at the provider's developer portal (links + steps inline on each `/connect/{provider}` page when env vars aren't set)
2. Set `{PROVIDER}_CLIENT_ID` + `{PROVIDER}_CLIENT_SECRET` on arena-web Vercel env

That's the whole story per provider. ~5 min each. Detail in `mission/pending-changes.md` "Provider OAuth bring-up."

Still pending Patrick's decisions:
- **Q1**: Stripe — flip to OAuth or keep manual API key forever? (Currently kept manual — payments are high-blast-radius.)
- **Q2** (NEW): Webhook HMAC signature verification — important before turning webhooks loose on production-critical flows. Not built yet (foundation exists; per-provider signature schemes deferred).

## Test plan once a provider is connected

1. **Test the no-connection handoff first** (before connecting): open Eve at `portal.maxnexus.io/dashboard/maxwell` → *"create a clickup task called 'first test'"* → Eve should reply with the connect URL, not silently fail
2. **Connect**: visit `arena.maxnexus.io/connect/clickup` → "Continue with ClickUp" → consent → land on settings page with green "Connected" banner
3. **Pick default**: live dropdown of your real ClickUp lists → choose one → Save
4. **Eve test for real**: same prompt → real task lands in the list you picked
5. **Verify audit log**: `arena.maxnexus.io/dashboard` → "Recent activity" panel → see the `task/create` entry with `mocked: false`
6. **Eve introspection**: ask Eve *"is anything broken?"* → `arena_failures` returns `healthy: true`
7. **Test failure handling**: rotate the ClickUp key on ClickUp's side → Eve fires another task → auth error → status flips to errored → email lands within 24h (if `RESEND_API_KEY` set)
8. **Repeat for Notion / GitHub / Slack** — same shape, different developer portal

## Critical files

```
arena-web/app/dashboard/page.tsx                                       ← user's dashboard
arena-web/app/connect/[provider]/page.tsx                              ← generic add (used by Stripe + manual fallbacks)
arena-web/app/connect/[provider]/[id]/edit/page.tsx                    ← generic edit
arena-web/app/connect/{clickup,notion,github,slack}/page.tsx           ← OAuth landing pages (provider-specific)
arena-web/app/connect/{clickup,notion,github,slack}/{Provider}ConnectClient.tsx ← landing UI
arena-web/app/connect/{clickup,notion,github,slack}/[id]/settings/page.tsx     ← per-connection settings
arena-web/app/connect/{clickup,notion,github,slack}/[id]/settings/{Provider}SettingsClient.tsx
arena-web/app/connect/{clickup,notion,github,slack}/manual/page.tsx    ← legacy manual fallback
arena-web/app/api/connections/route.ts                                 ← list/create/delete
arena-web/app/api/connections/[id]/route.ts                            ← per-connection get/patch
arena-web/app/api/connections/test/route.ts                            ← test before save
arena-web/app/api/oauth/{clickup,notion,github,slack}/start/route.ts   ← initiate OAuth flow
arena-web/app/api/oauth/{clickup,notion,github,slack}/callback/route.ts ← exchange code → token → persist
arena-web/app/api/oauth/clickup/lists/route.ts                         ← live list picker
arena-web/app/api/oauth/notion/databases/route.ts                      ← live database picker
arena-web/app/api/oauth/github/repos/route.ts                          ← live repo picker
arena-web/app/api/oauth/slack/channels/route.ts                        ← live channel picker
arena-web/app/api/task/{create,update}/route.ts                        ← Eve outbound (with needs_connection handoff)
arena-web/app/api/payment/route.ts                                     ← Eve outbound (Stripe)
arena-web/app/api/sync/push/route.ts                                   ← Eve outbound
arena-web/app/api/webhooks/[connectionId]/[secret]/route.ts            ← inbound webhooks
arena-web/lib/oauth/{clickup,notion,github,slack}.ts                   ← OAuth helpers per provider
arena-web/lib/providers/{clickup,notion,github,stripe,slack}.ts        ← provider implementations (read OAuth tokens or legacy)
arena-web/lib/providers/index.ts                                       ← registry + Provider interface
arena-web/lib/connection-health.ts                                     ← auto error tracking + notify
arena-web/lib/email/sendConnectionError.ts                             ← Resend integration
arena-web/lib/audit.ts                                                 ← arena_action_log writer
arena-web/lib/auth/session.ts                                          ← cookie auth (mirrors nexus-web)
arena-web/components/{ConnectionsList,RecentActions,FirstRunGuide}.tsx ← clean Apple-style baseline
nexus-web/app/api/eve/route.ts                                         ← Eve tool definitions + execution + needs_connection directive
```

## Schema migrations applied

- **022_arena_connection_notifications** — adds `arena_connections.error_notified_at TIMESTAMPTZ` for 24h notification throttle
- **023_arena_webhook_secret** — adds `arena_connections.webhook_secret TEXT NOT NULL`, default `encode(gen_random_bytes(24), 'hex')`, backfilled on existing rows
- **024_schedules** — `schedules` + `schedule_runs` tables for Operation Calendar (native scheduling)

Earlier migrations (017, 020, 021) created the original `arena_action_log` and `arena_connections` tables — pre-existing.

## Next steps

In rough priority:

1. **Per-provider HMAC verification on webhooks** — GitHub uses X-Hub-Signature-256, Stripe uses stripe-signature, Slack uses X-Slack-Signature + timestamp, ClickUp uses X-Signature. Add per-provider signature check before logging inbound events. Foundation exists; per-provider code deferred.
2. **Webhook → Eve trigger** — when a Slack `:done:` reaction lands on an Eve-posted message, post status update back into the conversation. Closes the loop.
3. **Connection-test cron** — every hour, hit `provider.testConnection()` for all active connections; auto-flip status before the user notices. Cheaper than waiting for the next Eve call to discover the breakage.
4. **External calendar sync** (Google / Apple) — ships as Arena providers; uses Operation Calendar's `external_event` table to flow back into native scheduling.
5. **Stripe OAuth + live-mode safeguards** — Q1 decision pending. If we go OAuth, Stripe Connect for split payments; if we stay manual, at minimum require an explicit `?live=1` confirmation dialog when an `sk_live_` key is pasted.
