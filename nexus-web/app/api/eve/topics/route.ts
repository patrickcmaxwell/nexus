import { NextResponse } from "next/server"
export const maxDuration = 30

import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"

import { getActiveAuthId } from "@/lib/auth/session"

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

// GET — fetch topics for a conversation
export async function GET(req: Request) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth()) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 })
  const { searchParams } = new URL(req.url)
  const conversationId = searchParams.get("conversationId")
  if (!conversationId) return new Response(JSON.stringify({ error: "Missing conversationId" }), { status: 400 })

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_topics")
    .select("*")
    .eq("user_id", USER_ID)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })

  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  return new Response(JSON.stringify({ topics: data ?? [] }), { headers: { "Content-Type": "application/json" } })
}

// POST — manually create a topic
export async function POST(req: Request) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth()) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 })
  const { conversationId, label, description, color } = await req.json()
  if (!conversationId || !label) return new Response(JSON.stringify({ error: "Missing fields" }), { status: 400 })

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_topics")
    .insert({ user_id: USER_ID, conversation_id: conversationId, label, description: description ?? "", color: color ?? "cyan" })
    .select()
    .single()

  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  return new Response(JSON.stringify({ topic: data }), { headers: { "Content-Type": "application/json" } })
}

// DELETE — remove a topic
export async function DELETE(req: Request) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth()) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 })
  const { id } = await req.json()
  const supabase = createServiceClient()
  await supabase.from("eve_topics").delete().eq("id", id).eq("user_id", USER_ID)
  return new Response(JSON.stringify({ success: true }), { headers: { "Content-Type": "application/json" } })
}
