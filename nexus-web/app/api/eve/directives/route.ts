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

// GET — list all directives/protocols
export async function GET() {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_directives")
    .select("*")
    .eq("user_id", USER_ID)
    .order("priority", { ascending: false })
    .order("created_at", { ascending: true })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ directives: data ?? [] })
}

// POST — create a new directive/protocol
export async function POST(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { type, title, content, priority = 0, target = "all" } = body
  if (!type || !title || !content) {
    return NextResponse.json({ error: "type, title, and content are required" }, { status: 400 })
  }
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_directives")
    .insert({ user_id: USER_ID, type, title, content, priority, target, is_active: true })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ directive: data })
}

// PATCH — update a directive
export async function PATCH(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { id, ...updates } = body
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_directives")
    .update(updates)
    .eq("id", id)
    .eq("user_id", USER_ID)
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ directive: data })
}

// DELETE — remove a directive
export async function DELETE(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("eve_directives")
    .delete()
    .eq("id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
