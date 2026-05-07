# Pending Changes

Proposed code changes waiting on a condition. Each entry has a **trigger** that determines when it can be applied.

---

## NEW (2026-05-07): Arena domain bring-up

**Trigger:** Patrick is ready to set up Arena as a real production service on `arena.talkcircles.io`.
**Context:** Arena is live at `https://arena-web-green.vercel.app` (Vercel-issued URL). It works today via that URL but cookie auth doesn't flow cleanly across subdomains until the custom domain lands. Once domain is wired, Arena and nexus-web share `nx_session` cookies via `SESSION_COOKIE_DOMAIN=.talkcircles.io`.

### Sequence (do in order)

1. **DNS** — In your DNS provider for `talkcircles.io`, add a record pointing `arena.talkcircles.io` at Vercel.
   - Vercel will tell you the exact target (CNAME `cname.vercel-dns.com.` or A records). Open Vercel dashboard → arena-web project → Settings → Domains → Add Domain → `arena.talkcircles.io` — it'll show the DNS instructions.
2. **Vercel domain attach** — Same Vercel screen. Vercel auto-issues TLS via Let's Encrypt once DNS resolves (usually 1-5 min after propagation).
3. **Cross-subdomain cookie env var** — In Vercel:
   - On `nexus-web` project → Environment Variables → add `SESSION_COOKIE_DOMAIN` = `.talkcircles.io` (note the leading dot)
   - On `arena-web` project → Environment Variables → add `SESSION_COOKIE_DOMAIN` = `.talkcircles.io`
   - Redeploy both (Vercel does this automatically on env var change).
4. **Resend key on arena-web** — Copy `RESEND_API_KEY` from nexus-web env to arena-web env. Without this, connection-error notification emails won't send (graceful — dashboard banner still shows, but no email).
5. **Eve points at custom domain** — On `nexus-web` project → Environment Variables → add `ARENA_BASE_URL` = `https://arena.talkcircles.io`. Without this, Eve's introspection tools (`arena_failures`, `arena_providers`) include the Vercel-issued URL in their "manage_url" responses.

### Optional (per-provider env vars)

You can leave these unset and let users supply credentials per-connection in the UI (recommended). If you want a fallback global default for solo use:
- `CLICKUP_API_KEY` — for the ClickUp provider
- (Notion/GitHub/Stripe/Slack don't have global env fallback in code yet — per-connection only.)

### Verification once DNS + env are in

```bash
# 1. Domain resolves and serves Arena
curl -I https://arena.talkcircles.io
# expect: HTTP/2 200 with vercel headers

# 2. Cross-subdomain cookie auth
# Open https://nexus-web-five-chi.vercel.app, sign in with face/passcode
# Then open https://arena.talkcircles.io/dashboard
# expect: lands directly on dashboard WITHOUT a sign-in prompt
# (if it asks you to sign in, SESSION_COOKIE_DOMAIN isn't set on both projects)

# 3. Health check
curl https://arena.talkcircles.io/api/health
# expect: {"ok":true,"providers":["clickup","notion","github","stripe","slack"]}
```

### Then test the full flow (per `mission/arena-platform.md`)

1. Open `arena.talkcircles.io/dashboard` — first-run guide appears
2. Click "Connect ClickUp" → paste API key + list id → save → connection appears
3. Click pencil → see webhook URL (https://arena.talkcircles.io/api/webhooks/...)
4. POST a test event to that webhook URL → audit log shows `inbound/clickup/...`
5. In nexus-web Eve chat: "create a task to test integration" → real ClickUp task lands
6. Ask Eve: "is anything broken?" → calls `arena_failures` → returns healthy

---

## NEW (2026-05-07): Push working tree to GitHub

**Trigger:** Patrick has a free moment.
**Context:** Extensive uncommitted work spans nexus-web (face-api fix, mobile fixes, Suits→agents rewrite), arena-web (webhook receiver + first-run + email + provider work), lumen (native face capture, Console window, sync engine), and mission docs.

```bash
cd /Users/shadow/code/nexus
git status                    # see scope of uncommitted work
git log --oneline -10         # see what's already committed
# Then commit grouping per mission convention — likely 5-7 logical commits:
#   - arena-web: standalone Next.js platform with 5 providers + webhooks
#   - nexus-web: mobile polish + Maxwell chat width fixes
#   - nexus-web: Suits page wired to real agents data
#   - nexus-web: face-api wasm fix for Lumen native login
#   - nexus-web: settings + console mobile layout
#   - lumen: native face capture + Console window + sync engine
#   - mission: arena-platform doc + nexus-web-polish doc + state refresh
git push origin main
```

Vera can't push from this environment.

---

## 0. Operation Multi-User — verify deploy + invite Londynn

**Trigger:** Director has time to test (asked to be reminded, 2026-05-05).
**Context:** All 4 phases committed locally (web schema/auth/UI, Lumen multi-user, iOS multi-user, invite-by-email). Director needs to:
1. Push to trigger Vercel: `cd ~/code/nexus && git push origin main`
2. Set `RESEND_API_KEY` on Vercel (Resend creds Director said he'd share)
3. Optionally set `RESEND_FROM` if a verified domain is configured (otherwise sender defaults to `Nexus <onboarding@resend.dev>`)

### Test checklist after Vercel build completes
1. `fetch('/api/auth/me')` in browser console → returns identity bundle (`humanId`, `email`, `isOwner: true`)
2. `fetch('/api/auth/known-users')` → returns array with Patrick + Merlin
3. `/auth/pin` with email + 4-digit PIN → redirects to `/auth/face`
4. `/` face scan → lands in dashboard
5. `/dashboard/humans` → invite Londynn (email + name + role) → confirm "Email sent" banner shows; she receives email at her inbox; she clicks link, sets PIN + face, lands in her dashboard
6. **Lumen** (already installed at `/Applications/Lumen.app`): quit + relaunch → AuthGate → email + PIN → MainView shows your avatar in toolbar. Avatar menu → "Add Another User" → log in as Merlin → conversations should disappear, briefing reloads as Merlin.
7. **iOS**: rebuild + install when ready. PIN screen has email field, top bar shows avatar pill.

If all 7 pass, multi-user is shipped end-to-end.

---

## 1. Lumen API key — read from environment, not hardcoded

**Trigger:** Xcode is closed (or stopped debugging `lumen-desktop`).
**File:** `lumen/lumen-desktop/lumen-desktop/LumenAPIManager.swift:72`
**Current:** `private let anthropicApiKey = "PASTE_YOUR_KEY_HERE"`
**Risk if left:** First time a real `sk-ant-…` key is pasted in, it will be one `git add` away from being committed to a public repo.

### Proposed replacement

Replace the line:
```swift
private let anthropicApiKey = "PASTE_YOUR_KEY_HERE"
```

With:
```swift
private var anthropicApiKey: String {
    // 1. Environment variable (Xcode scheme → Run → Environment Variables)
    if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
        return env
    }
    // 2. Keychain (recommended for production builds)
    if let kc = KeychainHelper.read(service: "com.nexus.lumen", account: "anthropic") {
        return kc
    }
    // 3. Fallback for legacy bundles
    return ""
}
```

You'll also need a tiny `KeychainHelper.swift` (Security framework wrapper) — happy to write it when Xcode is free.

### How to set the env var in Xcode

`Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables → +`
- Name: `ANTHROPIC_API_KEY`
- Value: your key
- ✅ Check "Encrypted in scheme" if available, otherwise add the scheme to `.gitignore`.

### Verification

After applying:
```bash
grep -r "PASTE_YOUR_KEY_HERE\|sk-ant-" lumen/lumen-desktop/
# should return nothing
```

---

## 2. Lumen `sessionCookie` is not persisted — re-auth required on every launch

**Trigger:** Xcode is closed (or stopped debugging `lumen-desktop`).
**File:** `lumen/lumen-desktop/lumen-desktop/LumenAPIManager.swift:10`
**Current:**
```swift
var sessionCookie: String?  // kept for nexus-web dashboard calls only
```
**Issue:** Plain `var` in memory only. On every Lumen relaunch the cookie is `nil`, so the user has to PIN/face-auth again. The DB session is still valid (14-day expiry) — the bug is purely client-side persistence.

### Proposed replacement

```swift
private static let sessionCookieKey = "lumen.sessionCookie"

var sessionCookie: String? {
    didSet {
        if let v = sessionCookie, !v.isEmpty {
            UserDefaults.standard.set(v, forKey: LumenAPIManager.sessionCookieKey)
        } else {
            UserDefaults.standard.removeObject(forKey: LumenAPIManager.sessionCookieKey)
        }
    }
}

// In init() (or computed property pattern matching localModel/voiceId):
//   self.sessionCookie = UserDefaults.standard.string(forKey: Self.sessionCookieKey)
```

**Companion fix in `AuthManager.swift`:** on launch, if `LumenAPIManager.shared.sessionCookie` is non-nil, set `isAuthenticated = true` immediately so the AuthGate is skipped.

```swift
init() {
    if let cookie = LumenAPIManager.shared.sessionCookie, !cookie.isEmpty {
        isAuthenticated = true
    }
}
```

Optional: validate the cookie against `/api/security/session-check` (or `/api/dashboard/overview` as a probe) before trusting it; if 401, drop the cookie and force re-auth.

### Verification

1. Build Lumen, PIN-auth.
2. Quit + relaunch.
3. Should land directly on the dashboard without seeing AuthGate.
4. `defaults read com.maxwell.lumen-desktop lumen.sessionCookie` should print the same UUID.

---

## 3. nexus-web `/api/security/pin` queries deprecated `team_members` table

**Trigger:** Anytime — non-Swift, no Xcode constraint. Apply during a non-test window for nexus-web.
**File:** `nexus-web/app/api/security/pin/route.ts:38-44`
**Issue:** PIN auth path looks up `team_members` while the rest of the security stack (`/api/security/face`) was migrated to `humans`. Today both tables exist (`team_members` HTTP 200 with rows; `humans` exists too) so the bug is latent — but the moment `team_members` is dropped, all team-member PIN logins break instantly. Owner login via `MAXWELL_PIN` env var would still work.

### Proposed replacement

Add a fallback to `humans` after the `team_members` lookup (with `pin_hash` column, if it exists in humans schema):

```ts
// 1. Try team_members (legacy, still authoritative until migration completes)
let { data: member } = await supabase
  .from("team_members")
  .select("id, name, role")
  .eq("pin_hash", pinHash)
  .eq("status", "active")
  .single()

// 2. Fallback to humans (post-migration target)
if (!member) {
  const { data: human } = await supabase
    .from("humans")
    .select("id, role")           // confirm column names — `name` may not exist in humans
    .eq("pin_hash", pinHash)
    .eq("status", "active")       // or .eq("active", true) — check schema
    .single()
  if (human) member = { id: human.id, name: "", role: human.role }
}
```

**Pre-flight:** confirm `humans` schema has `pin_hash` and an active flag before deploying. Quick check:
```bash
curl -s "$SUPA_URL/rest/v1/humans?select=id,pin_hash&limit=1" \
  -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY"
```

### Verification

1. Apply migration mapping a known team_member's `pin_hash` to a `humans` row.
2. POST to `/api/security/pin` with that PIN, expect `{ success: true }`.
3. Drop the team_members row, repeat — should still succeed via `humans` fallback.
