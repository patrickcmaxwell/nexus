import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

async function getSessionMemberId() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return null
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("team_member_id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()
  if (!data || data.invalidated || new Date(data.expires_at) < new Date()) return null
  return data.team_member_id
}

// GET — list all operations with record count and assigned agents
export async function GET() {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operations")
    .select(`
      *,
      operation_records(count),
      operation_agents(
        role_in_op,
        agents(id, name, role, status)
      )
    `)
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ operations: data ?? [] })
}

// POST — create a new operation
export async function POST(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
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

  // Write permissions mapping
  await supabase.from("data_permissions").insert({
    resource_type: "operation",
    resource_id: data.id,
    owner_id: currentHumanId,
    visibility: body.visibility || "private"
  })

  return NextResponse.json(data)
}

// PATCH — update an operation
export async function PATCH(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
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

// DELETE — remove an operation
export async function DELETE(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
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
