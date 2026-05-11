// /api/terminal/sessions/[id]
//
// Per-session updates. Lumen PATCHes this with heartbeat + snapshot
// every 30s, and again with status='exited' (or 'error') when the PTY
// child terminates. iOS doesn't write here — it only reads via the list
// endpoint or submits commands via /api/terminal/commands.
import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { checkDesktopAuth } from "@/lib/desktop-auth"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const VALID_STATUS = new Set(["running", "exited", "error"])

// PATCH — Lumen pushes any of: last_snapshot, last_snapshot_at, status,
// exit_code, ended_at, title. last_heartbeat_at is always touched.
export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const { id } = await params
  const body = await req.json().catch(() => ({})) as Record<string, unknown>
  const patch: Record<string, unknown> = { last_heartbeat_at: new Date().toISOString() }

  if (typeof body.last_snapshot === "string") {
    patch.last_snapshot = body.last_snapshot
    patch.last_snapshot_at = new Date().toISOString()
  }
  if (typeof body.title === "string") {
    patch.title = body.title
  }
  if (typeof body.status === "string" && VALID_STATUS.has(body.status)) {
    patch.status = body.status
    if (body.status !== "running" && !body.ended_at) {
      patch.ended_at = new Date().toISOString()
    }
  }
  if (typeof body.exit_code === "number") {
    patch.exit_code = body.exit_code
  }
  if (typeof body.ended_at === "string") {
    patch.ended_at = body.ended_at
  }

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("terminal_sessions")
    .update(patch)
    .eq("id", id)
    .eq("user_id", userId)
    .select("id, status, last_heartbeat_at")
    .single()
  if (error || !data) {
    return NextResponse.json({ error: error?.message ?? "not found" }, { status: 404 })
  }
  return NextResponse.json(data)
}

// GET — single-session read; iOS viewer uses this to refresh while open.
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const { id } = await params
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("terminal_sessions")
    .select("id, mac_label, folder, claude_path, title, status, exit_code, last_snapshot, last_snapshot_at, last_heartbeat_at, started_at, ended_at")
    .eq("id", id)
    .eq("user_id", userId)
    .single()
  if (error || !data) {
    return NextResponse.json({ error: "not found" }, { status: 404 })
  }
  return NextResponse.json(data)
}
