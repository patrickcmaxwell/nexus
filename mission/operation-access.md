# Operation Access — Auth that protects people who didn't build it

**Status:** ACTIVE (2026-05-05)
**Owner:** Director (Patrick) + Vera
**Scope:** Identity, recovery, and access-point design for everyone who joins Nexus.

---

## The framing

Director (2026-05-05):
> "I did build this. And Patrick is trying to help everyone else use it.
> What we have to do to help everyone else use it properly and also protect them.
> That is what we're gonna have to do."

This operation isn't "make auth secure." Patrick can secure his own surface — face, PIN, recovery via direct DB access. The problem is **everyone else**: Merlin, Londynn, every future invitee. They didn't build the system. They don't know what an RLS policy is. They will:

- Forget their PIN
- Lose their device with the active session
- Have their PIN observed
- Pick weak secrets if not nudged
- Lock themselves out and not know what to do
- Never read documentation

The job is to give them **strong defaults**, **friendly recovery**, and **safe failure modes**, without requiring them to understand how any of it works.

---

## The unsolved problem

**A brain-stored secret that is all four of these at once:**

| Pillar | What it means | Where common methods fail |
|---|---|---|
| 1. Memorable | Recall without writing | Random passwords fail |
| 2. High-entropy | Brute-force / dictionary attack fails | 4-digit PINs fail |
| 3. Unique to you | Not derivable from your public profile | "Favorite song" fails (Spotify wrap leaks it) |
| 4. Observation-resistant | Watching/recording you doesn't replay | Typed passwords fail (shoulder-surf), face fails (photo) |

Every production auth method picks 2-3 and skips one. **No mass-market system has nailed all four with a brain-only secret.**

### Five angles explored (2026-05-05)

A. **Combinatorial melodies** — secret = 3 short snippets from 3 songs in order. Knowing one of your songs doesn't unlock; knowing all three plus order does. Entropy multiplies.

B. **Personalized mutation** — public song with a deliberate change (wrong note, doubled tempo, hum on a phrase). The mutation IS the secret. Observation gives the song, not the deviation.

C. **Tempo / timing fingerprint** — melody is public; *your* tap rhythm is the secret. Microsecond inter-onset intervals are biometric.

D. **Compose, don't borrow** — user writes a 7-note melody nobody else knows. Tradeoff: harder to recall reliably than a known song.

E. **Multi-factor combo (best candidate)** — face gates the prompt (proves liveness), then a registered song with personal mutation at user's tempo confirms it's you and not just your face. Each factor compensates for what the others lack.

Director hasn't picked an angle yet — captured for design conversation.

---

## What's shipped (Phase 4-7 of Operation Multi-User → folded here)

### Identity
- `humans.email` is the identity primitive (Phase 1 migration 019)
- `humans.is_owner=true` = root of trust (Patrick only, not transferable yet)
- `humans.role` ∈ {observer, collaborator, operator, admin}
- `humans.auth_id` bridges to `auth.users` for data ownership (FK target)

### Authentication paths
- **Face** (`/api/security/face`) — biometric, identifies via descriptor distance
- **Email + PIN** (`/api/security/pin`) — identity-first, eliminates PIN-collision
- **Owner passphrase** (`/api/passphrase`) — env-var fallback, owner-only
- **Self-service PIN rotation** (`/api/auth/change-pin`) — invalidates other sessions on rotation

### Multi-admin redundancy (Phase 7, shipping today)
Any admin or owner can act as a "key holder" — recovery for any other user.
- **`/api/admin/lock-user`** — invalidates sessions + flips status to disabled. Owner cannot be locked.
- **`/api/admin/reset-credentials`** — issues fresh invite token, target re-onboards. Owner cannot be reset (separate recovery path needed).
- **`/api/admin/audit-log`** — last N admin actions for accountability.
- Per-row `Lock` / `Reset` icons on `/dashboard/humans`. `Audit log` button in header.
- All actions write to `security_log` with actor + target + reason.

---

## Open design decisions

### Owner recovery (urgent before more humans join)
If Patrick's face *and* PIN are both compromised, no current path restores him without direct DB access. Three options proposed (2026-05-05):
- **A. N-of-M trusted contacts** — designated humans can together issue Patrick a recovery token.
- **B. Single trusted contact** — Patrick nominates one human (Merlin? Londynn?) for unilateral restore.
- **C. Recovery codes** — printable one-time codes Patrick stashes in a safe.

**Director hasn't picked.** Combination is plausible (B + C: trusted contact for normal recovery, codes for if both are unreachable).

### PIN length policy
Director suggested earlier (2026-05-05): owners can use 4-digit PINs, non-owners must use 6+. Rationale: owner has face fallback, non-owners are the wider attack surface.
- **Min length for non-owners**: 6 (matches Apple/iOS) or 8?
- **Grandfather Merlin** (currently has 4-digit) or force rotate on next login?

### Audit log visibility
- Owner only?
- All admins (current default)?
- Everyone sees their own actions?

### Initial key-holder designation
Today only Patrick (`is_owner=true`, `role=admin`). Merlin is `role=observer`. Londynn is unborn.
- Promote Merlin to admin when he's ready, or wait for vetted candidates?
- How does Patrick decide who becomes a key holder? Documented criteria?

---

## What "protecting them" actually means

Concrete user-experience guarantees the system should make for non-builders:

0. **Protection access stays fast.** Director (2026-05-05): "even a tone from the right person you should have that tone. Can go in there and protect people." Key holders are not gatekeepers behind multi-step approvals — they're duty-bound responders. One click from `/dashboard/humans` per row to lock, reset, or restore. The system trusts the credential, gets out of the way, and logs the action.
1. **No silent failures.** Every error message tells the user what to try next. "Invalid credentials" → "Use Face Scan instead, or contact Patrick."
2. **Recovery is one click away.** When stuck, user always sees a "I can't get in" link that triggers the right flow (admin-assisted reset, recovery code prompt, etc).
3. **Bad defaults are blocked.** If a user picks a weak PIN ("0000", "1234", repeating digits), the form rejects with friendly explanation, not just an error code.
4. **Observation safety is visible.** UI cues when entering credentials in a public space — e.g. PIN dots that don't show the digit you just typed.
5. **Compromise is announced.** When an admin locks/resets a user, the user gets a clear next-steps email or in-app banner — not just sudden 401s.
6. **Logs are readable.** Audit log uses plain English ("Patrick locked Merlin's account at 3:42 PM, reason: lost phone"), not event codes.
7. **Default to safe.** New users default to `observer` role, not `admin`. PIN min length defaults to 6 unless explicitly granted owner privileges.

---

## Phases

### Phase A — Admin redundancy ✅ (shipped 2026-05-05)
Lock / Reset / Audit endpoints + UI. See "What's shipped" above.

### Phase B — Owner recovery (next, blocking more invites)
Pick from the 3 proposed options above. Build the chosen path. Test by simulating Patrick's lockout.

### Phase C — Hardened defaults
- PIN length policy (6+ for non-owners, friendly error for weak choices)
- Bad-PIN dictionary (reject `0000`, `1234`, birthdays?, repeating digits)
- Owner can be force-required to set both face *and* PIN (no single-factor accounts at the top of trust)

### Phase D — Friendly errors + recovery UI
Every auth error message gets a "what to try next" line.
"I can't get in" link from every auth screen.

### Phase E — Audit log polish
Plain-English event labels.
Filter by user / event / time range.
Export.

### Phase F — Song-snippet auth (research/spike)
Pick an angle from the five (or a combination). Build a prototype. Test with non-builders to see if it's actually memorable and reproducible.

### Phase G — Multi-sig consensus (later)
N-of-M approval for the most sensitive actions: ownership transfer, demoting an admin, mass session invalidation. Defer until team > 5 humans.

---

## References

- `mission/operation-multi-user.md` — original schema/auth migration that this builds on.
- `mission/enhancements-backlog.md` — song-snippet auth detailed sketch.
- Supabase migration `019_multi_user_unification.sql` — schema baseline.
- `lib/auth/admin.ts` — admin-gate helper.
