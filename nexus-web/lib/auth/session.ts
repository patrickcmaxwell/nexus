// Session-based identity helper. Replaces the hardcoded `USER_ID` constant
// that used to be sprinkled across 28+ API routes. Reads the `nx_session`
// cookie, joins `security_sessions` → `humans`, and returns the active
// human's identity bundle.
//
// Why two ids:
//   - `humanId`  = `humans.id`        — used for profile/team/role concerns
//                                       and for `security_sessions.team_member_id`
//   - `authId`   = `humans.auth_id`   — points to `auth.users.id`, used as
//                                       `user_id` in user-scoped data tables
//                                       (eve_history, operations, eve_memory,
//                                       etc). All FKs on those tables ref
//                                       `auth.users`, not `humans`.
//
// Routes that scope user data MUST use `authId`. Routes that scope identity
// (sessions, invites, team listings) use `humanId`.

import { cookies } from "next/headers"
import { createClient } from "@supabase/supabase-js"

const COOKIE = "nx_session"

export type ActiveHuman = {
  humanId: string
  authId: string | null
  email: string
  displayName: string
  handle: string | null
  role: string
  isOwner: boolean
  status: string
  sessionId: string
  authMethod: string | null
}

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

/// Returns the active human if a valid session exists, else null. Use this
/// in route handlers and gate the result with a 401 when null.
export async function getActiveHuman(): Promise<ActiveHuman | null> {
  const sessionId = (await cookies()).get(COOKIE)?.value
  if (!sessionId) return null

  const supabase = getServiceClient()

  const { data: session } = await supabase
    .from("security_sessions")
    .select("id, team_member_id, expires_at, invalidated, auth_method")
    .eq("id", sessionId)
    .single()

  if (!session) return null
  if (session.invalidated) return null
  if (new Date(session.expires_at) < new Date()) return null
  if (!session.team_member_id) return null

  const { data: human } = await supabase
    .from("humans")
    .select("id, auth_id, email, display_name, handle, role, is_owner, status")
    .eq("id", session.team_member_id)
    .single()

  if (!human || human.status !== "active") return null

  return {
    humanId: human.id,
    authId: human.auth_id,
    email: human.email,
    displayName: human.display_name,
    handle: human.handle,
    role: human.role,
    isOwner: human.is_owner,
    status: human.status,
    sessionId: session.id,
    authMethod: session.auth_method,
  }
}

/// Convenience: returns the auth.users id for use as `user_id` in data
/// queries. Returns null when there's no session or the active human hasn't
/// linked an auth.users row yet (invited but never completed setup).
export async function getActiveAuthId(): Promise<string | null> {
  const h = await getActiveHuman()
  return h?.authId ?? null
}

/// Helper for routes that historically used the hardcoded const. Returns
/// the auth_id when there's a session, OR a temporary fallback when an
/// explicit override env (for cron/admin tooling) is provided.
export async function requireActiveAuthId(): Promise<{ authId: string } | { error: Response }> {
  const authId = await getActiveAuthId()
  if (!authId) {
    return {
      error: new Response(
        JSON.stringify({ error: "Not authenticated" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      ),
    }
  }
  return { authId }
}
