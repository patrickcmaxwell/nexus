import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

// GET /api/arena/log?limit=50&action=task/create&caller=eve
// Returns recent rows from public.arena_action_log. Used by Lumen / iOS to
// surface "what has Eve actually done?" — the audit trail for arena calls.
export async function GET(req: NextRequest) {
  if (!await checkDesktopAuth(req)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { searchParams } = new URL(req.url)
  const limit  = Math.min(parseInt(searchParams.get("limit") ?? "50", 10) || 50, 200)
  const action = searchParams.get("action")
  const caller = searchParams.get("caller")

  const supabase = createServiceClient()
  let query = supabase
    .from("arena_action_log")
    .select("id, action, caller, payload, result, status, error_msg, created_at")
    .order("created_at", { ascending: false })
    .limit(limit)

  if (action) query = query.eq("action", action)
  if (caller) query = query.eq("caller", caller)

  const { data, error } = await query
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ entries: data ?? [] })
}
