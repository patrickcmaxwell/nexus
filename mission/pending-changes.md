# Pending Changes

Proposed code changes waiting on a condition. Each entry has a **trigger** that determines when it can be applied. Newest at top.

---

## ⭐ TOP PRIORITY (2026-05-08): Provider OAuth bring-up

**Trigger:** Patrick wants Eve to act through any of the 4 OAuth providers (ClickUp / Notion / GitHub / Slack).

**Context:** Each provider's `/connect/{provider}` page detects whether `{PROVIDER}_CLIENT_ID` is set. If not, it shows an inline 5-6 step admin guide with the exact steps to register an OAuth app + paste the redirect URL + add Vercel env vars. Once env vars are set, the page flips to a "Continue with {Provider}" button.

### Sequence — same for every provider (~5 min each)

| Provider | Where to register | Redirect URL | Vercel env vars |
|---|---|---|---|
| **ClickUp** | Avatar (upper-right) → Settings → **Apps** → OAuth Apps → Create new app | `https://arena.maxnexus.io/api/oauth/clickup/callback` | `CLICKUP_CLIENT_ID` + `CLICKUP_CLIENT_SECRET` |
| **Notion** | https://www.notion.so/my-integrations → New integration → **Public** | `https://arena.maxnexus.io/api/oauth/notion/callback` | `NOTION_CLIENT_ID` + `NOTION_CLIENT_SECRET` |
| **GitHub** | https://github.com/settings/developers → OAuth Apps → New OAuth App | `https://arena.maxnexus.io/api/oauth/github/callback` | `GITHUB_CLIENT_ID` + `GITHUB_CLIENT_SECRET` |
| **Slack** | https://api.slack.com/apps → Create New App → From scratch | `https://arena.maxnexus.io/api/oauth/slack/callback` | `SLACK_CLIENT_ID` + `SLACK_CLIENT_SECRET` |

**Slack also needs Bot Token Scopes:** `chat:write`, `chat:write.public`, `channels:read`, `groups:read` (added on the same OAuth & Permissions page where the redirect URL goes).

### Test path (recommended order: ClickUp first since it's the simplest)

1. **Test the missing-connection handoff FIRST** (before connecting anything):
   - Open Eve at `portal.maxnexus.io/dashboard/maxwell`
   - *"create a clickup task called 'first test'"*
   - Eve should reply with the connect URL and ask you to sign in first — not silently fake success or error
2. **Activate ClickUp**: register app + set Vercel env vars, then visit `arena.maxnexus.io/connect/clickup` → "Continue with ClickUp" → consent → land on settings page → pick default list → Save
3. **Eve test for real**: same prompt as step 1 → real task lands in ClickUp
4. Repeat with Notion / GitHub / Slack as desired

### Stripe is intentionally NOT on OAuth

Stripe is the 5th provider but stays on manual API key (`/connect/stripe`). Reason: payments are high-blast-radius and shouldn't be casually wired. Decision Q1 in `/code/echo/decisions.md` — flip to OAuth or keep manual?

---

## ⭐ Push working tree to GitHub

**Trigger:** Patrick has a free moment.

**Context:** Extensive uncommitted work spans nexus-web, arena-web, maxnexus-public, lumen, and mission docs. Suggested commit grouping (each is a meaningful chunk):

```bash
cd /Users/shadow/code/nexus
git status                    # see scope
git log --oneline -10         # what's already committed

# Commit grouping (rough):
#   - arena-web: 4 OAuth providers (clickup, notion, github, slack) + per-connection settings pages
#   - arena-web: Eve handoff for missing connection in /api/task/create
#   - nexus-web: design system primitives + UserAvatar + theme lockdown
#   - nexus-web: full HUD chrome scrub + DashboardHome rebuild + auth pages clean
#   - nexus-web: per-entity detail routes (humans/[id], agents/[id], operations/[id])
#   - nexus-web: Operation Calendar (schedules + runner + Eve tools + UI)
#   - nexus-web: Lumen face-api wasm fix (server-side)
#   - lumen: native face capture + Console window + sync engine (held until Xcode at checkpoint)
#   - mission: state/handoff/journal/pending-changes/arena-platform refresh
git push origin main
```

Vera can't push from this environment.

---

## ✅ DONE 2026-05-07: Arena domain bring-up

DNS, custom domain, env vars all set by Patrick. Arena live at `https://arena.maxnexus.io` with cross-subdomain cookie auth from `portal.maxnexus.io`. Splash at `https://maxnexus.io`. Test flow remains in `mission/arena-platform.md`.

---

## ✅ DONE 2026-05-05/06: Operation Multi-User verify + invite Londynn

End-to-end shipped. Multi-user PIN + face + email auth working in prod. Londynn's invite flow tested. Lumen multi-user committed; iOS code committed (rebuild pending).

---

## Lumen pending — pending Patrick at his Mac

### 1. Lumen API key — read from env / Keychain, not hardcoded

**Trigger:** Xcode is closed (or stopped debugging `lumen-desktop`).
**File:** `lumen/lumen-desktop/lumen-desktop/LumenAPIManager.swift:72`
**Current:** `private let anthropicApiKey = "PASTE_YOUR_KEY_HERE"`
**Risk:** First time a real `sk-ant-…` key is pasted in, it's one `git add` away from being committed to a public repo.

Replacement pattern:
```swift
private var anthropicApiKey: String {
    if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
    if let kc = KeychainHelper.read(service: "com.nexus.lumen", account: "anthropic") { return kc }
    return ""
}
```
Plus a small `KeychainHelper.swift` (Security framework wrapper).

### 2. Lumen `sessionCookie` not persisted — re-auth on every launch

**Trigger:** Xcode is closed.
**File:** `lumen/lumen-desktop/lumen-desktop/LumenAPIManager.swift:10`
**Current:** plain `var sessionCookie: String?` — lives only in memory, lost on quit.

Replacement: persist via UserDefaults with `didSet` watcher; restore on init. Skip AuthGate when cookie is present + valid.

---

## Future hardening items (no urgency, no blocker)

### Per-provider webhook HMAC verification

**Trigger:** Anyone wants to wire a real provider webhook to Arena.
**File:** `arena-web/app/api/webhooks/[connectionId]/[secret]/route.ts`
**Current:** Path-token authentication only — anyone with the URL can post events.
**Why deferred:** Each provider has its own signature scheme (GitHub `X-Hub-Signature-256`, Stripe `stripe-signature` with timestamp, Slack `X-Slack-Signature`, ClickUp `X-Signature`). Foundation works; verification is per-provider code.

### Connection-test cron

**Trigger:** Eve discovers connection breakage too late ("hey ClickUp 401'd, you should rotate"). 
**Approach:** Vercel Cron hits `/api/connections/health-check` hourly → calls `provider.testConnection()` for every active connection → flips status to errored on auth failures (using existing `recordConnectionResult` helper). Email throttle already in place.

### External calendar sync (Google / Apple Calendar)

**Trigger:** Patrick wants Operation Calendar schedules to mirror to / from his external calendar.
**Approach:** Two new Arena providers (`google-calendar`, `apple-calendar`) that write `external_event` rows back into `schedules` table. Same OAuth pattern as the 4 existing providers.

### Operation Mirror — cross-surface chat parity

**Trigger:** iOS rebuild + install completes (so we have all 3 surfaces functioning to test parity).
**Approach:** Supabase Realtime channels per conversation; iOS + Lumen + web all subscribe; optimistic local writes with retry; conflict resolution for rare cross-device edits.

### Operation Documents — PDF RAG

**Trigger:** Patrick has appetite to start.
**Approach:** File upload in Eve chat → Supabase Storage → background chunk + embed → pgvector table → retrieval injection into Eve's system prompt → Eve `search_documents` tool.
