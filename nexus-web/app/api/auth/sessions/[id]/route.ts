// /api/auth/sessions/[id] — revoke a single session belonging to the active human.
//
// DELETE — invalidates the session row scoped to the active human's
//          team_member_id (so callers can only revoke their own sessions, not
//          someone else's).
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

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { id } = await params
  if (!id) return NextResponse.json({ error: "Session id required" }, { status: 400 })

  const supabase = getServiceClient()
  const { error } = await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("id", id)
    .eq("team_member_id", me.humanId)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // If the caller revoked the session they're using, drop the cookie so the
  // next request starts clean instead of dangling on an invalidated id.
  const response = NextResponse.json({ success: true })
  if (id === me.sessionId) {
    response.cookies.delete("nx_session")
    response.cookies.delete("mn_pin_verified")
    response.cookies.delete("mn_face_verified")
  }
  return response
}
