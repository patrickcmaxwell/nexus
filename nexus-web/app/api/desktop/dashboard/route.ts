import { NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"

import { getActiveAuthId } from "@/lib/auth/session"

/**
 * GET /api/desktop/dashboard
 * Lightweight endpoint for the Electron desktop app HeroDashboard.
 * No auth required — app runs locally, data is not sensitive for display.
 */
export async function GET() {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const supabase = createServiceClient()

  const [{ data: directives }, { data: agents }, { data: ops }] = await Promise.all([
    supabase
      .from("eve_directives")
      .select("id, directive, created_at")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false })
      .limit(6),
    supabase
      .from("agents")
      .select("id, name, role, status, last_scanned_at, total_findings")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: true })
      .limit(8),
    supabase
      .from("operations")
      .select("id, title, status, updated_at")
      .eq("user_id", USER_ID)
      .in("status", ["active", "in_progress"])
      .order("updated_at", { ascending: false })
      .limit(5),
  ])

  return NextResponse.json(
    { directives: directives ?? [], agents: agents ?? [], operations: ops ?? [] },
    {
      headers: {
        "Access-Control-Allow-Origin": "http://localhost:5173",
        "Access-Control-Allow-Methods": "GET",
      },
    }
  )
}

export async function OPTIONS() {
  return new NextResponse(null, {
    headers: {
      "Access-Control-Allow-Origin": "http://localhost:5173",
      "Access-Control-Allow-Methods": "GET",
    },
  })
}
