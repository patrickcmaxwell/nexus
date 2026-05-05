import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

import { getActiveAuthId } from "@/lib/auth/session"

// GET — load messages for a specific conversation
export async function GET(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const conversationId = req.nextUrl.searchParams.get("conversationId")
  if (!conversationId) return NextResponse.json({ error: "Missing conversationId" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_history")
    .select("id, role, content, created_at")
    .eq("user_id", USER_ID)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .limit(200)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  // Reverse to chronological order (oldest first)
  return NextResponse.json({ messages: (data ?? []).reverse() })
}

// POST — save a message to a conversation
export async function POST(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { conversation_id, role, content } = await req.json()
  if (!conversation_id || !role || !content) return NextResponse.json({ error: "Missing fields" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase.from("eve_history").insert({
    user_id: USER_ID,
    conversation_id,
    role,
    content,
  })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}

// DELETE — clear history for a specific conversation (or all if no conversationId)
export async function DELETE(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const body = await req.json().catch(() => ({}))
  const query = supabase.from("eve_history").delete().eq("user_id", USER_ID)
  if (body?.conversationId) {
    await query.eq("conversation_id", body.conversationId)
  } else {
    await query
  }
  return NextResponse.json({ success: true })
}
