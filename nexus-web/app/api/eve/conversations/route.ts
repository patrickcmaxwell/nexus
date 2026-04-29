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

// GET — list all conversations
export async function GET() {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_conversations")
    .select("id, title, source, created_at, updated_at")
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
    .limit(500)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ conversations: data ?? [] })
}

// POST — create new conversation, returns id
export async function POST(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { title } = await req.json().catch(() => ({}))
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_conversations")
    .insert({
      user_id: USER_ID,
      title: title ?? "New Session",
    })
    .select("id, title, created_at, updated_at")
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ conversation: data })
}

// PATCH — update conversation title
export async function PATCH(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id, title } = await req.json()
  if (!id || !title) return NextResponse.json({ error: "Missing id or title" }, { status: 400 })
  const supabase = createServiceClient()
  await supabase.from("eve_conversations").update({ title, updated_at: new Date().toISOString() }).eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ ok: true })
}

// DELETE — delete conversation and its messages
export async function DELETE(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "Missing id" }, { status: 400 })
  const supabase = createServiceClient()
  await supabase.from("eve_history").delete().eq("conversation_id", id).eq("user_id", USER_ID)
  await supabase.from("eve_conversations").delete().eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ ok: true })
}
