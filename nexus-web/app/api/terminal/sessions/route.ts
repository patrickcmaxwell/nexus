// /api/terminal/sessions
//
// Cross-device terminal bridge. Lumen on the Mac registers a session
// when it spawns one, then PATCHes the row (snapshot + heartbeat) every
// 30s while running. iOS reads this surface to render the terminal list.
//
// See migration 026_terminal_bridge.sql for the full architecture note.
import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { checkDesktopAuth } from "@/lib/desktop-auth"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// GET — list this user's terminal sessions.
//
// Returns active (running) sessions first, then recent exits. We use
// heartbeat staleness > 2 min to mark a 'running' row as 'stale' so iOS
// can warn the user when Lumen has crashed without cleaning up.
export async function GET(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("terminal_sessions")
    .select("id, mac_label, folder, claude_path, title, status, exit_code, last_snapshot, last_snapshot_at, last_heartbeat_at, started_at, ended_at")
    .eq("user_id", userId)
    .order("started_at", { ascending: false })
    .limit(50)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // Promote stale 'running' rows to 'stale' in the response so iOS shows
  // the right pill without us writing back to the DB on every read.
  const now = Date.now()
  const STALE_MS = 2 * 60 * 1000
  const promoted = (data ?? []).map(s => {
    if (s.status === "running" && s.last_heartbeat_at) {
      const hb = new Date(s.last_heartbeat_at).getTime()
      if (now - hb > STALE_MS) return { ...s, status: "stale" }
    }
    return s
  })
  return NextResponse.json({ sessions: promoted })
}

// POST — Lumen registers a freshly-spawned session.
//
// Body: { mac_label?, folder, claude_path?, title? }
export async function POST(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const body = await req.json().catch(() => ({})) as {
    mac_label?: string
    folder?: string
    claude_path?: string
    title?: string
  }
  if (!body.folder) {
    return NextResponse.json({ error: "folder required" }, { status: 400 })
  }
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("terminal_sessions")
    .insert({
      user_id: userId,
      mac_label: body.mac_label ?? null,
      folder: body.folder,
      claude_path: body.claude_path ?? null,
      title: body.title ?? null,
      status: "running",
    })
    .select("id, started_at")
    .single()
  if (error || !data) {
    return NextResponse.json({ error: error?.message ?? "insert failed" }, { status: 500 })
  }
  return NextResponse.json(data, { status: 201 })
}
