import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

// GET /api/agents/activity?agent_id=<uuid>&limit=50
// Recent activity for a single agent. Used by Lumen / iOS / web to show
// scan history, status changes, findings count over time.
export async function GET(req: NextRequest) {
  if (!await checkDesktopAuth(req)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const { searchParams } = new URL(req.url)
  const agentId = searchParams.get("agent_id")
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "50", 10) || 50, 200)

  if (!agentId) {
    return NextResponse.json({ error: "agent_id required" }, { status: 400 })
  }

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("agent_activity")
    .select("id, action, details, created_at")
    .eq("user_id", USER_ID)
    .eq("agent_id", agentId)
    .order("created_at", { ascending: false })
    .limit(limit)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ activity: data ?? [] })
}
