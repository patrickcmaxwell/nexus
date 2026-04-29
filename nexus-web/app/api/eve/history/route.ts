import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"
import { createServiceClient } from "@/lib/supabase/service"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

async function checkAuth() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return false
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()
  if (!data || data.invalidated) return false
  return new Date(data.expires_at) > new Date()
}

// GET — load messages for a specific conversation
export async function GET(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
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

// DELETE — clear history for a specific conversation (or all if no conversationId)
export async function DELETE(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
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
