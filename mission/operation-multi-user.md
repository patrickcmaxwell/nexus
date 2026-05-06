# Operation Multi-User — Identity, Invites, Session Switching

**Status:** PLANNING (2026-05-05)
**Owner:** Director (Patrick) + Vera
**Why now:** Director wants Londynn invited to the team. Current auth model can't distinguish two users with the same PIN, schema is duplicated/broken, and Lumen has no concept of "switch user" for shared devices.

---

## Investigation findings (don't re-discover)

### Schema confusion — TWO parallel users tables
- `humans` — used by `/api/security/face` and `/api/team/invite`. Has `id, handle, display_name, role, status, pin_hash, face_descriptor, seed_face_descriptor, is_owner, invite_token, created_at`.
- `team_members` — used by `/api/security/pin` and `/api/team/setup`. Same conceptual fields but different name.
- This means **the existing invite flow is broken end-to-end**: invite POST writes to `humans`, but the setup page (where the invitee lands) reads from `team_members` and won't find the row.
- Code comment in `face/route.ts`: "team_member_id maps to humans.id (migrated)" — suggests an in-progress migration that never finished.

### Three auth paths — only face works for multi-user identity
1. **Face** (`/api/security/face`) — iterates all active humans, computes Euclidean distance vs stored descriptor, picks lowest under 0.6 threshold. **Identifies the user properly.**
2. **PIN** (`/api/security/pin`) — hashes input PIN, queries `team_members WHERE pin_hash = X AND status = 'active'`. Uses `.single()` — if two members have the same PIN, the query throws or returns one arbitrarily. **Cannot distinguish users with collision.**
3. **Passphrase** (`/api/passphrase`) — compares plaintext to `MAXWELL_PIN` env var, hardcodes `user_id = "director"`. Legacy single-user path Patrick still uses. **No identity at all.**

### Sessions
- `security_sessions` table: `id` (cookie value), `user_id`, `team_member_id`, `expires_at`, `last_verified_at`, `invalidated`, `auth_method`.
- Cookie name: `nx_session` (httpOnly, 14-day sliding window).
- Lumen: `AuthManager.handleSessionCookie(value)` stuffs the cookie value into `LumenAPIManager.shared.sessionCookie` for all subsequent API calls.

### Roles already defined
`observer | collaborator | operator | admin` — plus `humans.is_owner=true` for Patrick.

### Patrick's stated entry points
- "FaceTime" → reading as existing webcam face descriptor flow (face-api.js + 128-dim Euclidean match)
- Passcode → the PIN

---

## Architecture decisions

### D1. Unify on `humans` table
`team_members` was an early naming. `humans` is more canonical and already used by the newer surfaces (face auth, invite POST). Kill `team_members` after migrating any rows.

### D2. PIN auth requires identity hint
Login form: `[email or handle] + [PIN]`. Lookup is `humans WHERE lower(email)=lower(input) AND pin_hash=hash(input)` — eliminates collision possibility regardless of duplicate PINs.

Add `email` field to `humans` (currently only has `handle`, `display_name`). Email is the right identity primitive — universal, memorable, future-proof for password resets.

### D3. Face auth stays unchanged
Face IS identity — the descriptor match returns one specific human. No identity hint needed.

### D4. Multi-session in Lumen
Mirror of `LumenAppRegistry` pattern just shipped:
- `LumenAuthRegistry` (ObservableObject, owned by App root) holds `[AuthSession]`
- Each `AuthSession` has `human` info, `nx_session` cookie, last-active timestamp
- One session is "active" at a time — `LumenStore` keys conversations/briefing/etc to active session
- Top-bar avatar menu: "Switch User" → list of cached sessions + "Login as someone new"
- Switching user: re-prompt for PIN (security default — don't trust cached cookies for switch)
- Sign out current user: invalidate session server-side, drop from registry

Cookie storage: macOS Keychain per user (one entry per `humans.id`). Default to "remember this user" so the login form pre-populates.

### D5. Migration path for current data
- Patrick is the only "real" active user today (with face + admin role). Merlin was "invited" but the invite flow is broken so likely no `humans` row.
- Migration: ensure Patrick's `humans` row has an `email`, his existing PIN hash works under the new lookup. No data loss.

---

## Phased plan

### Phase 0 — Schema audit (BEFORE migrating)
- Query Supabase: `SELECT * FROM humans;` and `SELECT * FROM team_members;` — confirm what's actually there.
- Confirm Patrick's owner row id, current PIN hash, role.
- Confirm if Merlin made it into either table.
- **Director approves results before we touch schema.**

### Phase 1 — Supabase schema fix
- ADD `email TEXT UNIQUE` (case-insensitive collation) to `humans`
- BACKFILL Patrick's email
- (If `team_members` has rows not in `humans`) MIGRATE them
- DROP `team_members` table
- Update `humans` RLS policy to allow service-role inserts/selects (already in place from earlier work)

### Phase 2 — Backend rewrites
- `/api/security/pin` → take `{ email, pin }`, look up `humans` by email, verify hash, create session
- `/api/team/setup` → use `humans` (was `team_members`); fix the broken invite flow
- `/api/team/invite` → already uses `humans`, works after Phase 1
- NEW `/api/auth/me` → reads cookie, returns `{ human, role, isOwner }`
- NEW `/api/auth/known-users` → returns active humans for user-switcher (no PINs leaked, just `id, display_name, email, avatar_url`)
- NEW `/api/auth/switch` → `{ targetEmail, pin }` — verifies, swaps session, returns new cookie
- `/api/passphrase` — keep as backwards-compat, but route through `humans` lookup (drop hardcoded "director")

### Phase 3 — Web auth UI
- New login page: email + PIN form, face button
- New `/dashboard/team` admin page: invite form, member list, role editor
- Fix `/invite/[token]` to use `humans`

### Phase 4 — Lumen multi-user
- `LumenAuthRegistry` ObservableObject + per-user Keychain cookie storage
- AuthGate redesigned: face primary, "Use PIN instead" reveals email + PIN
- Top-bar avatar with switch menu
- `LumenStore.didSwitchActiveUser` → flush conversations, refetch dashboard, refetch briefing

### Phase 5 — Test + invite Londynn
- Patrick logs in fresh under his email + PIN
- Patrick invites Londynn via `/dashboard/team` → invite link sent
- Londynn opens invite on her device → onboards (PIN + optional face)
- Patrick on his Mac: avatar menu → "Login as new user" → enters Londynn's email + PIN → swaps to her context
- Patrick switches back to himself
- Verify: conversations are isolated, briefings are isolated, no cross-contamination

### Phase 6 — Vercel deploy
- nexus-web changes go up after Patrick approves the schema migration
- Lumen build ships after nexus-web is live (so the auth endpoints exist)
- Don't push without explicit approval

---

## Open questions for Director

1. **Identity field**: email confirmed as the username, or prefer something else (handle, name)?
2. **"FaceTime"** in the original message → confirming this means the existing webcam face descriptor flow, not the literal FaceTime app. Right?
3. **Switch-user re-verification**: PIN re-prompt every switch (secure default), or trust cached sessions for X minutes? Recommend re-prompt always.
4. **iOS scope**: extend multi-user to nexus-ios in this pass, or ship Lumen+web first and iOS gets it next? Recommend ship-first.
5. **`team_members` table contents**: anything in there I shouldn't lose? (Will dump rows in Phase 0 before dropping.)

---

## Risks

- **Existing nx_session cookies invalidated** on schema change — every active session will need to re-login. Patrick logs in once after deploy. Acceptable.
- **Vercel deploy + Supabase migration order** — if web ships before schema, login breaks; if schema ships before web, old web breaks too. Strategy: migration first (additive: add `email` column), then web deploy (uses new column), then drop `team_members`. Three deploys, zero downtime window if ordered right.
- **Lumen ships after web** — old Lumen.app keeps working until rebuilt because the cookie format and `nx_session` flow don't change. Just the login form changes.

---

## Checkpoints (Director must approve to proceed)

- [ ] Phase 0 dump approved → proceed to migration
- [ ] Phase 1 migration applied (Director runs / Vera runs with approval)
- [ ] Phase 2 backend code review approved
- [ ] Phase 3 web UI lands → Director tests login flow
- [ ] Phase 4 Lumen build → Director tests user switching
- [ ] Phase 5 Londynn invite sent → onboarding completes
