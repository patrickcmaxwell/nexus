# Pending Changes

Proposed code changes waiting on a condition. Each entry has a **trigger** that determines when it can be applied.

---

## ✅ DONE 2026-05-07: Arena domain bring-up

DNS, custom domain, env vars all set by Patrick. Arena is live at `https://arena.maxnexus.io` with cross-subdomain cookie auth from `portal.maxnexus.io`. Splash at `https://maxnexus.io` (passphrase doorway). All previously-listed bring-up steps complete.

Test flow remains in `mission/arena-platform.md` "Test plan once domain is live."

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
