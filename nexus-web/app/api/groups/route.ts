import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { resolveHumanId } from "@/lib/desktop-auth"

export async function GET(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("groups")
    .select(`id, name, description, created_by, created_at, group_members(human_id, joined_at, role, humans(display_name, handle))`)
    .order("created_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ groups: data, currentHumanId })
}

export async function POST(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { name, description } = body
  if (!name) return NextResponse.json({ error: "name is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data: group, error } = await supabase
    .from("groups")
    .insert({ name, description: description ?? "", created_by: currentHumanId })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  await supabase.from("group_members").insert({ group_id: group.id, human_id: currentHumanId, role: "owner" })
  return NextResponse.json(group)
}

export async function PATCH(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { id, name, description } = body
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })
  const supabase = createServiceClient()
  const updates: Record<string, string> = {}
  if (name) updates.name = name
  if (description !== undefined) updates.description = description
  const { data, error } = await supabase.from("groups").update(updates).eq("id", id).select().single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

export async function DELETE(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase.from("groups").delete().eq("id", id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
