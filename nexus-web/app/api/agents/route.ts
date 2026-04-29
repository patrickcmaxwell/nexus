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

// GET — list all agents
export async function GET() {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("agents")
    .select("*")
    .eq("user_id", USER_ID)
    .order("created_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// POST — create a new agent
export async function POST(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { name, role, personality, capabilities, directives, status, visibility } = body
  if (!name || !role) return NextResponse.json({ error: "name and role are required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("agents")
    .insert({
      user_id: USER_ID,
      name,
      role,
      personality: personality ?? "",
      capabilities: capabilities ?? [],
      directives: directives ?? "",
      status: status ?? "standby",
    })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // Write permissions mapping
  await supabase.from("data_permissions").insert({
    resource_type: "agent",
    resource_id: data.id,
    owner_id: currentHumanId,
    visibility: visibility || "private"
  })

  return NextResponse.json(data)
}

// PATCH — update an agent
export async function PATCH(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { id, ...updates } = body
  if (!id) return NextResponse.json({ error: "id is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("agents")
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq("id", id)
    .eq("user_id", USER_ID)
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// DELETE — remove an agent
export async function DELETE(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("agents")
    .delete()
    .eq("id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
