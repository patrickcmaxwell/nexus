// Admin-only IP unblock + listing.
//
// Hardened 2026-05-08: previously used the auth-scoped supabase client
// (which on this codebase never returns a real user — we use security_sessions
// not auth.users for identity) and had no role check. Any cookied request
// could delete entries from ip_blocklist and forge security_log rows.
//
// Now: requires owner OR admin role via getActiveHuman(); uses the service
// client so writes actually succeed regardless of RLS posture.
import { NextRequest, NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"

async function requireAdmin() {
  const me = await getActiveHuman()
  if (!me) return { error: NextResponse.json({ error: "Not authenticated" }, { status: 401 }) }
  if (!me.isOwner && me.role !== "admin") {
    return { error: NextResponse.json({ error: "Admin only" }, { status: 403 }) }
  }
  return { me }
}

export async function DELETE(req: NextRequest) {
  const auth = await requireAdmin()
  if ("error" in auth) return auth.error
  const { me } = auth

  const { ip } = await req.json().catch(() => ({}))
  if (!ip || typeof ip !== "string") {
    return NextResponse.json({ error: "IP address required" }, { status: 400 })
  }

  const supabase = createServiceClient()
  const { error } = await supabase
    .from("ip_blocklist")
    .delete()
    .eq("ip_address", ip)

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  await supabase.from("security_log").insert({
    user_id: me.humanId,
    event: "ip_unblocked",
    ip_address: ip,
    metadata: { unblocked_by: me.email },
  })

  return NextResponse.json({ success: true, unblocked: ip })
}

export async function GET() {
  const auth = await requireAdmin()
  if ("error" in auth) return auth.error

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("ip_blocklist")
    .select("*")
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ blocked: data })
}
