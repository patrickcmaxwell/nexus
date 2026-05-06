// GET /api/admin/audit-log?limit=50
//
// Returns recent security_log entries scoped to admin events
// (admin.lock_user, admin.reset_credentials, etc.). Used by the
// /dashboard/humans audit panel so any key holder can see who did what
// to whom — accountability + post-incident review.
//
// Available to any admin (or owner). Non-admins get 403.
import { NextRequest, NextResponse } from "next/server"
import { requireAdmin, getServiceClient } from "@/lib/auth/admin"

export async function GET(req: NextRequest) {
  const gate = await requireAdmin()
  if ("error" in gate) return gate.error

  const limitParam = req.nextUrl.searchParams.get("limit")
  const limit = Math.min(Math.max(parseInt(limitParam ?? "50", 10) || 50, 1), 200)

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("security_log")
    .select("id, event, user_id, metadata, created_at")
    .like("event", "admin.%")
    .order("created_at", { ascending: false })
    .limit(limit)

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ entries: data ?? [] })
}
