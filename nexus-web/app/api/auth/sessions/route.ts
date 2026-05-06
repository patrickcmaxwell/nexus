// /api/auth/sessions — list and bulk-revoke the active human's sessions.
//
// GET   — returns all non-invalidated, non-expired sessions for the current
//         human, with the current session flagged.
// DELETE — body: { scope: "others" | "all" }. "others" signs out every
//         device EXCEPT this one (the common "sign out everywhere" UX).
//         "all" invalidates every session including the current — caller
//         will be 401'd on the next request.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { getActiveHuman } from "@/lib/auth/session"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

export async function GET() {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("security_sessions")
    .select("id, created_at, last_verified_at, expires_at, auth_method")
    .eq("team_member_id", me.humanId)
    .eq("invalidated", false)
    .gt("expires_at", new Date().toISOString())
    .order("last_verified_at", { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({
    currentSessionId: me.sessionId,
    sessions: (data ?? []).map((s) => ({ ...s, current: s.id === me.sessionId })),
  })
}

export async function DELETE(req: NextRequest) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { scope } = await req.json().catch(() => ({}))
  if (scope !== "others" && scope !== "all") {
    return NextResponse.json({ error: "scope must be 'others' or 'all'" }, { status: 400 })
  }

  const supabase = getServiceClient()
  let q = supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("team_member_id", me.humanId)
  if (scope === "others") q = q.neq("id", me.sessionId)
  const { error } = await q
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const response = NextResponse.json({ success: true })
  if (scope === "all") {
    response.cookies.delete("nx_session")
    response.cookies.delete("mn_pin_verified")
    response.cookies.delete("mn_face_verified")
  }
  return response
}
