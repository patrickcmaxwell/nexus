import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"
import { NextResponse } from "next/server"

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

export async function POST(req: Request) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth()) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { label, description, tags, source_conversation_id } = await req.json()

  if (!label) {
    return NextResponse.json({ error: "label is required" }, { status: 400 })
  }

  const supabase = createServiceClient()

  const { data, error } = await supabase
    .from("nexus_map_nodes")
    .insert({
      user_id: USER_ID,
      label,
      description: description ?? "",
      tags: tags ?? [],
      source_conversation_id: source_conversation_id ?? null,
    })
    .select()
    .single()

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ success: true, node: data })
}
