import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { isAuthed, USER_ID } from "@/lib/operations/auth"

// GET — single record with children (nested research) and any source context
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()

  const [{ data: record, error }, { data: children }, { data: research }] = await Promise.all([
    supabase.from("operation_records").select("*").eq("id", id).eq("user_id", USER_ID).single(),
    supabase
      .from("operation_records")
      .select("id, title, type, content, created_at, status, pinned")
      .eq("parent_record_id", id)
      .eq("user_id", USER_ID)
      .is("archived_at", null)
      .order("created_at", { ascending: true }),
    supabase
      .from("research_jobs")
      .select("id, status, prompt, model, started_at, completed_at, error, progress_note")
      .eq("record_id", id)
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false })
      .limit(1),
  ])

  if (error || !record) return NextResponse.json({ error: "Not found" }, { status: 404 })
  return NextResponse.json({ record, children: children ?? [], latestResearch: research?.[0] ?? null })
}

// PATCH — edit any field on the record
const ALLOWED_FIELDS = new Set([
  "title", "content", "type", "priority", "status", "pinned", "archived_at",
])

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const body = await req.json()

  const update: Record<string, unknown> = {}
  for (const key of Object.keys(body)) {
    if (ALLOWED_FIELDS.has(key)) update[key] = body[key]
  }
  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "No valid fields to update" }, { status: 400 })
  }

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operation_records")
    .update(update)
    .eq("id", id)
    .eq("user_id", USER_ID)
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// DELETE — hard delete. For soft-delete, PATCH archived_at instead.
export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("operation_records")
    .delete()
    .eq("id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
