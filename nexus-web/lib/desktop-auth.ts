import { cookies } from "next/headers"
import { createServiceClient } from "./supabase/service"
import type { NextRequest } from "next/server"

export async function resolveSessionId(req: NextRequest): Promise<string | null> {
  const auth = req.headers.get("Authorization")
  if (auth?.startsWith("Bearer ")) return auth.slice(7)
  const cookieStore = await cookies()
  return cookieStore.get("nx_session")?.value ?? null
}

export async function checkDesktopAuth(req: NextRequest): Promise<boolean> {
  const sessionId = await resolveSessionId(req)
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

export async function resolveHumanId(req: NextRequest): Promise<string | null> {
  const sessionId = await resolveSessionId(req)
  if (!sessionId) return null
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("team_member_id, user_id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()
  if (!data || data.invalidated || new Date(data.expires_at) < new Date()) return null
  // team_member_id is set for team_member sessions; user_id is set for owner PIN sessions
  return data.team_member_id ?? data.user_id ?? null
}
