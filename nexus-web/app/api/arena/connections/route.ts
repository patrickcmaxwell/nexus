// /api/arena/connections
//
// Read-only proxy for Arena's per-user connection state, scoped to the
// active human. Powers Lumen's Arena tab in the Console + the in-nexus
// /dashboard/arena panel. Until Lumen can reach arena.talkcircles.io
// directly via the cross-subdomain cookie share, this endpoint gives the
// desktop app a single, session-authenticated read path.
//
// Writes still happen on arena-web — this is read-only by design.

import { NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const ARENA_BASE = process.env.ARENA_BASE_URL || "https://arena-web-green.vercel.app"

export async function GET() {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  // Fetch connections + provider catalog in parallel. Catalog comes from
  // arena-web's /api/health (canonical source — adding a new provider
  // there auto-flows here without nexus-web code changes).
  const supabase = createServiceClient()
  const [connectionsRes, healthRes] = await Promise.all([
    supabase
      .from("arena_connections")
      .select("id, provider, label, status, last_used_at, last_error, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false }),
    fetch(`${ARENA_BASE}/api/health`, { signal: AbortSignal.timeout(4_000) }).catch(() => null),
  ])

  let providers: Array<{ id: string; name: string; methods: string[] }> = []
  if (healthRes?.ok) {
    const json = await healthRes.json().catch(() => ({})) as { providers?: typeof providers }
    providers = json.providers ?? []
  }

  return NextResponse.json({
    connections: connectionsRes.data ?? [],
    providers,
    manage_url: `${ARENA_BASE}/dashboard`,
  })
}
