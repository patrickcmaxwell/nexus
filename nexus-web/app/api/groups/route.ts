import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"

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

// GET — list all groups
export async function GET() {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  
  // Fetch groups and their members
  const { data, error } = await supabase
    .from("groups")
    .select(`
      id, name, description, created_by, created_at,
      group_members(human_id, joined_at, role, humans(display_name, handle))
    `)
    .order("created_at", { ascending: false })
    
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ groups: data, currentHumanId })
}

// POST — create a new group
export async function POST(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  
  const body = await req.json()
  const { name, description } = body
  if (!name) return NextResponse.json({ error: "name is required" }, { status: 400 })
  
  const supabase = createServiceClient()
  
  // 1. Check if user is Operator or Admin
  const { data: human } = await supabase.from("humans").select("role").eq("id", currentHumanId).single()
  if (!human || (human.role !== 'operator' && human.role !== 'admin')) {
      return NextResponse.json({ error: "Only operators and admins can create groups." }, { status: 403 })
  }

  // 2. Insert the group
  const { data: group, error } = await supabase
    .from("groups")
    .insert({
      name,
      description: description ?? "",
      created_by: currentHumanId,
    })
    .select()
    .single()
    
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // 3. Automatically add creator to the group as owner
  await supabase.from("group_members").insert({
      group_id: group.id,
      human_id: currentHumanId,
      role: "owner"
  })

  return NextResponse.json(group)
}

// PATCH — update a group
export async function PATCH(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  
  const body = await req.json()
  const { id, name, description } = body
  if (!id || (!name && description === undefined)) return NextResponse.json({ error: "id and at least one field to update required" }, { status: 400 })
  
  const supabase = createServiceClient()

  // Verify requester is group owner or system admin
  const { data: member } = await supabase.from("group_members").select("role").eq("group_id", id).eq("human_id", currentHumanId).single()
  const { data: human } = await supabase.from("humans").select("role").eq("id", currentHumanId).single()

  if ((!member || member.role !== 'owner') && human?.role !== 'admin') {
      return NextResponse.json({ error: "Only group owners or admins can modify a group." }, { status: 403 })
  }

  const updates: any = {}
  if (name) updates.name = name
  if (description !== undefined) updates.description = description

  const { data, error } = await supabase.from("groups").update(updates).eq("id", id).select().single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// DELETE — completely delete a group
export async function DELETE(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  
  const body = await req.json()
  const { id } = body
  if (!id) return NextResponse.json({ error: "id is required" }, { status: 400 })
  
  const supabase = createServiceClient()

  // Verify requester is group owner or system admin
  const { data: member } = await supabase.from("group_members").select("role").eq("group_id", id).eq("human_id", currentHumanId).single()
  const { data: human } = await supabase.from("humans").select("role").eq("id", currentHumanId).single()

  if ((!member || member.role !== 'owner') && human?.role !== 'admin') {
      return NextResponse.json({ error: "Only group owners or admins can delete a group." }, { status: 403 })
  }

  const { error } = await supabase.from("groups").delete().eq("id", id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
