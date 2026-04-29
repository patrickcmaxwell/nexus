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

// POST — join a group
export async function POST(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  
  const body = await req.json()
  const { group_id } = body
  if (!group_id) return NextResponse.json({ error: "group_id is required" }, { status: 400 })
  
  const supabase = createServiceClient()

  // Insert the group member
  const { data, error } = await supabase
    .from("group_members")
    .insert({
      group_id,
      human_id: currentHumanId,
    })
    
  // Ignores unique constraint violations (already a member) gracefully
  if (error && error.code !== '23505') {
      return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ success: true })
}

// DELETE - leave a group
export async function DELETE(req: NextRequest) {
    const currentHumanId = await getSessionMemberId()
    if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    
    const body = await req.json()
    const { group_id } = body
    if (!group_id) return NextResponse.json({ error: "group_id is required" }, { status: 400 })
    
    const supabase = createServiceClient()
  
    const { error } = await supabase
      .from("group_members")
      .delete()
      .eq("group_id", group_id)
      .eq("human_id", currentHumanId)
      
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  
    return NextResponse.json({ success: true })
}
