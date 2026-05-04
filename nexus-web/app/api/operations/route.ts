import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { resolveHumanId } from "@/lib/desktop-auth"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

export async function GET(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operations")
    .select(`*, operation_records(count), operation_agents(role_in_op, agents(id, name, role, status))`)
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ operations: data ?? [] })
}

export async function POST(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { name, codename, description, objectives, status, priority, directives, tags } = body
  if (!name) return NextResponse.json({ error: "name is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operations")
    .insert({
      user_id: USER_ID,
      name,
      codename: codename ?? null,
      description: description ?? "",
      objectives: objectives ?? "",
      status: status ?? "planning",
      priority: priority ?? "medium",
      directives: directives ?? "",
      tags: tags ?? [],
    })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  await supabase.from("data_permissions").insert({
    resource_type: "operation",
    resource_id: data.id,
    owner_id: currentHumanId,
    visibility: body.visibility || "private",
  })
  return NextResponse.json(data)
}

export async function PATCH(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { id, ...updates } = body
  if (!id) return NextResponse.json({ error: "id is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operations")
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq("id", id)
    .eq("user_id", USER_ID)
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

export async function DELETE(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("operations")
    .delete()
    .eq("id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
