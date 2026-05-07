# Arena Web

**Arena is the executor that takes Eve's tool calls and turns them into real-world action** — ClickUp tasks, payments, sync pushes, and more. This Next.js app is both the user-facing connections platform AND the API surface Eve calls into.

Replaces the previous standalone Express service (`/code/nexus/arena/`) with a single deployable web product.

---

## What's here

- **Public landing** at `/` — explains Arena, lets a Nexus user connect their account
- **Dashboard** at `/dashboard` — your connections, action history, status per provider
- **Connect flow** at `/connect/[provider]` — wire a new external service (ClickUp, Stripe, Notion, …)
- **Action endpoints** at `/api/task/create`, `/api/task/update`, `/api/payment/route`, `/api/sync/push` — what Eve calls when running an arena tool
- **Audit log** at `/api/log` — read-back of action history (filterable)
- **Health check** at `/api/health` — service alive + active provider configs

---

## Auth model

Subdomain cookie share. nexus-web sets `nx_session` cookie with `Domain=.talkcircles.io` so any subdomain of `talkcircles.io` (including `arena.talkcircles.io`) can read it. Arena's middleware validates the cookie against the shared Supabase `security_sessions` table → identifies the active human → all subsequent reads + writes are scoped to that human's `arena_connections` rows.

For Eve's executor calls (server-to-server), we use the `ARENA_SECRET` shared bearer token — these don't go through the user-cookie path.

---

## Provider abstraction

Every external integration follows the same `Provider` interface in `lib/providers/index.ts`:

```ts
interface Provider {
  id: string
  name: string
  description: string
  isConfigured: () => boolean
  createTask?(input: CreateTaskInput): Promise<TaskResult>
  updateTask?(input: UpdateTaskInput): Promise<TaskResult>
  routePayment?(input: PaymentInput): Promise<PaymentResult>
  syncPush?(input: SyncPushInput): Promise<SyncResult>
}
```

To add a new integration: create `lib/providers/<name>.ts`, implement the methods you support, register in `lib/providers/index.ts`. The UI lights up the new provider automatically; Eve's tool routing picks it up via the registry.

ClickUp is the first concrete provider (`lib/providers/clickup.ts`). Stripe, Notion, GitHub, Slack are explicit "next" candidates.

---

## Local dev

```bash
cp .env.example .env.local
# Fill in NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ARENA_SECRET
pnpm install
pnpm dev    # listens on :3001
```

Apply the schema migration once against your Supabase project:
```bash
# From nexus-web (which already has the supabase CLI wired)
supabase db push --include arena-web/supabase/migrations
```

Or run the SQL directly via the Supabase dashboard.

---

## Deploy

Single Vercel project. Point at `arena-web/` as the root directory. Set env vars (`SUPABASE_*`, `ARENA_SECRET`, optionally `CLICKUP_*`). Once a custom domain like `arena.talkcircles.io` is wired, set `SESSION_COOKIE_DOMAIN=.talkcircles.io` so the cross-subdomain cookie share works.

---

## Differences from old Express service

| | Old (`/code/nexus/arena/`) | New (`/code/nexus/arena-web/`) |
|---|---|---|
| Stack | Express 5 | Next.js 16 + React 19 |
| Surface | API only | API + UI |
| Auth | Bearer token only | Bearer (Eve) + cookie session (users) |
| Deploy | bring-your-own host | Vercel one-click |
| Providers | hardcoded mocks | abstract interface, registry-driven |

The old service can be removed once the new app is live and Eve's `lib/arena/client.ts` points at the new base URL.
