// /api/oauth/notion/databases?connection_id=...
// Returns databases the connected integration has access to.
import { NextRequest, NextResponse } from "next/server"
import { getActiveAuthId } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { searchDatabases } from "@/lib/oauth/notion"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const connectionId = req.nextUrl.searchParams.get("connection_id")
  if (!connectionId) return NextResponse.json({ error: "connection_id required" }, { status: 400 })

  const supabase = getServiceClient()
  const { data: conn } = await supabase
    .from("arena_connections")
    .select("credentials")
    .eq("id", connectionId)
    .eq("user_id", userId)
    .eq("provider", "notion")
    .maybeSingle()
  if (!conn) return NextResponse.json({ error: "Connection not found" }, { status: 404 })

  const accessToken = (conn.credentials as Record<string, string> | null)?.access_token
  if (!accessToken) return NextResponse.json({ error: "Connection has no access token — re-authorize" }, { status: 400 })

  try {
    const databases = await searchDatabases(accessToken)
    return NextResponse.json({ databases })
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : "Notion search failed" }, { status: 502 })
  }
}
