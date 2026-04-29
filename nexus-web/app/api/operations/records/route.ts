import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"

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

// GET — records for a specific operation
export async function GET(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { searchParams } = new URL(req.url)
  const operationId = searchParams.get("operation_id")
  if (!operationId) return NextResponse.json({ error: "operation_id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operation_records")
    .select("*")
    .eq("operation_id", operationId)
    .eq("user_id", USER_ID)
    .order("created_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// POST — add a record to an operation
export async function POST(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { operation_id, type, title, content, source, priority } = body
  if (!operation_id || !title) return NextResponse.json({ error: "operation_id and title required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operation_records")
    .insert({
      operation_id,
      user_id: USER_ID,
      type: type ?? "note",
      title,
      content: content ?? "",
      source: source ?? "manual",
      priority: priority ?? "normal",
    })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// DELETE — remove a record
export async function DELETE(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("operation_records")
    .delete()
    .eq("id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
