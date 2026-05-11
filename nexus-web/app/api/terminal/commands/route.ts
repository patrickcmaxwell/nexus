// /api/terminal/commands
//
// Command queue between iOS (submitter) and Lumen (dispatcher).
//
//   iOS  POST {session_id, command}   → row inserted with status='pending'
//   Lumen GET ?session_id=…&since=…   → pulls pending rows for its sessions
//   Lumen PATCH /[id] status='dispatched' once it has fed bytes into the PTY
//
// Why a queue table instead of e.g. websocket push: the iOS app is
// already a REST client. A queue table is durable, survives Lumen
// restarts (commands sit in 'pending' until Lumen comes back), and gives
// us an audit trail of "what did the phone tell my Mac to do."
import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { checkDesktopAuth } from "@/lib/desktop-auth"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// POST — iOS submits a command for one of the user's sessions.
//
// Body: { session_id, command }   command is raw bytes; typically ends \n
export async function POST(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const body = await req.json().catch(() => ({})) as {
    session_id?: string
    command?: string
  }
  if (!body.session_id || !body.command) {
    return NextResponse.json({ error: "session_id and command required" }, { status: 400 })
  }
  const supabase = createServiceClient()

  // Make sure the caller owns this session before queuing a command for
  // it. Without this check, any authenticated user could write into any
  // session whose id they guessed.
  const { data: session, error: sErr } = await supabase
    .from("terminal_sessions")
    .select("id, status")
    .eq("id", body.session_id)
    .eq("user_id", userId)
    .single()
  if (sErr || !session) {
    return NextResponse.json({ error: "session not found" }, { status: 404 })
  }
  if (session.status !== "running") {
    return NextResponse.json({ error: "session not running" }, { status: 409 })
  }

  const { data, error } = await supabase
    .from("terminal_commands")
    .insert({
      session_id: body.session_id,
      user_id: userId,
      command: body.command,
      status: "pending",
    })
    .select("id, submitted_at, status")
    .single()
  if (error || !data) {
    return NextResponse.json({ error: error?.message ?? "insert failed" }, { status: 500 })
  }
  return NextResponse.json(data, { status: 201 })
}

// GET — Lumen polls for pending commands. Pass session_id (required) to
// scope to a single session, plus optional since=<iso> to skip already-
// seen rows. Empty session_id is invalid — Lumen should poll per session,
// not for the whole workspace, so it can't accidentally pick up commands
// addressed to a session it doesn't own (e.g. a session on another Mac
// signed in as the same user later).
export async function GET(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const { searchParams } = new URL(req.url)
  const sessionId = searchParams.get("session_id")
  const since = searchParams.get("since")
  if (!sessionId) {
    return NextResponse.json({ error: "session_id required" }, { status: 400 })
  }

  const supabase = createServiceClient()
  let q = supabase
    .from("terminal_commands")
    .select("id, session_id, command, status, submitted_at, dispatched_at")
    .eq("session_id", sessionId)
    .eq("user_id", userId)
    .eq("status", "pending")
    .order("submitted_at", { ascending: true })
    .limit(100)
  if (since) q = q.gt("submitted_at", since)
  const { data, error } = await q
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ commands: data ?? [] })
}
