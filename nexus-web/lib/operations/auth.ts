import { cookies } from "next/headers"
import { createServiceClient } from "@/lib/supabase/service"

/**
 * Legacy "single-user" identity. Patrick's auth.users.id. Kept as a const
 * for backward compatibility with routes that still reference it directly,
 * but new code should call `getActiveAuthId()` from `@/lib/auth/session`
 * to support multi-user isolation.
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
 * (Kept as the team_member_id name for compatibility — points at humans.id
 * after the multi-user migration unified the two tables.)
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
 * Returns the full human record for the current session. The shape mirrors
 * what callers expected when this came from `team_members`, so existing
 * call sites keep working — `name` is mapped from `display_name`.
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
    .from("humans")
    .select("id, display_name, role, email, status")
    .eq("id", memberId)
    .single()
  if (!data) return null
  return {
    id: data.id,
    name: data.display_name,
    role: data.role,
    email: data.email,
    status: data.status,
  }
}
