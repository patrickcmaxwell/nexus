import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@/lib/supabase/server"

// Admin-only: unblock an IP address
export async function DELETE(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { ip } = await req.json()
  if (!ip) {
    return NextResponse.json({ error: "IP address required" }, { status: 400 })
  }

  const { error } = await supabase
    .from("ip_blocklist")
    .delete()
    .eq("ip_address", ip)

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  await supabase.from("security_log").insert({
    user_id: user.id,
    event: "ip_unblocked",
    ip_address: ip,
    metadata: { unblocked_by: user.email },
  })

  return NextResponse.json({ success: true, unblocked: ip })
}

// List all currently blocked IPs
export async function GET(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

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
