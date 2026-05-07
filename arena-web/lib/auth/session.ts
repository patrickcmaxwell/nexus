import { cookies } from "next/headers"
import { getServiceClient } from "@/lib/supabase/service"

// Cross-subdomain cookie share: nexus-web sets `nx_session` with
// `Domain=.talkcircles.io` so every subdomain (including arena) can read
// the same cookie. We validate it against the shared `security_sessions`
// table and resolve to a humans row + auth_id for data scoping.

const COOKIE = "nx_session"

export type ActiveHuman = {
  humanId: string
  authId: string
  email: string
  displayName: string
  role: string
  isOwner: boolean
}

export async function getActiveHuman(): Promise<ActiveHuman | null> {
  const sessionId = (await cookies()).get(COOKIE)?.value
  if (!sessionId) return null

  const supabase = getServiceClient()

  const { data: session } = await supabase
    .from("security_sessions")
    .select("id, team_member_id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()

  if (!session || session.invalidated) return null
  if (new Date(session.expires_at) < new Date()) return null
  if (!session.team_member_id) return null

  const { data: human } = await supabase
    .from("humans")
    .select("id, auth_id, email, display_name, role, is_owner, status")
    .eq("id", session.team_member_id)
    .single()

  if (!human || human.status !== "active") return null
  if (!human.auth_id) return null  // unbridged accounts can't own arena_connections

  return {
    humanId: human.id,
    authId: human.auth_id,
    email: human.email,
    displayName: human.display_name,
    role: human.role,
    isOwner: human.is_owner,
  }
}

/// Convenience for routes that just need the auth_id (the FK target on
/// arena_connections.user_id).
export async function getActiveAuthId(): Promise<string | null> {
  const me = await getActiveHuman()
  return me?.authId ?? null
}
