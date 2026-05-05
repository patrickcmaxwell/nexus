// GET /api/auth/known-users — list active humans for the user-switcher UI.
// Returns only public profile fields (no PIN hashes, no face descriptors,
// no auth_ids). Available to ANY authenticated session — the active user
// needs to see who else exists on the team to pick a switch target.
import { NextResponse } from "next/server"
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
  if (!me) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  }

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("humans")
    .select("id, email, display_name, handle, role, is_owner, avatar_url")
    .eq("status", "active")
    .order("is_owner", { ascending: false })
    .order("created_at", { ascending: true })

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({
    activeHumanId: me.humanId,
    users: (data ?? []).map(h => ({
      humanId: h.id,
      email: h.email,
      displayName: h.display_name,
      handle: h.handle,
      role: h.role,
      isOwner: h.is_owner,
      avatarUrl: h.avatar_url,
    })),
  })
}
