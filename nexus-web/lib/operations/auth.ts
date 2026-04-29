import { cookies } from "next/headers"
import { createServiceClient } from "@/lib/supabase/service"

/**
 * The original single-user identity for this Nexus deployment.
 * Used as a fallback when team_member_id is not available in the session.
 */
export const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

/**
 * Returns true if the nx_session cookie maps to a valid, un-invalidated,
 * non-expired security session row in Supabase.
 */
export async function isAuthed(): Promise<boolean> {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return false
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()
  if (!data || data.invalidated) return false
  return new Date(data.expires_at) > new Date()
}

/**
 * Returns the team_member_id from the current session, or null if not found.
 */
export async function getSessionMemberId(): Promise<string | null> {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return null
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("team_member_id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()
  if (!data || data.invalidated || new Date(data.expires_at) < new Date()) return null
  return data.team_member_id || null
}

/**
 * Returns the full team member record for the current session.
 */
export async function getSessionMember(): Promise<{
  id: string
  name: string
  role: string
  email: string | null
  status: string
} | null> {
  const memberId = await getSessionMemberId()
  if (!memberId) return null
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("team_members")
    .select("id, name, role, email, status")
    .eq("id", memberId)
    .single()
  return data || null
}
