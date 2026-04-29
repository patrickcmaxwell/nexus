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

// DELETE — kick a member from a group
export async function DELETE(req: NextRequest) {
  const currentHumanId = await getSessionMemberId()
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  
  const body = await req.json()
  const { group_id, target_human_id } = body
  if (!group_id || !target_human_id) return NextResponse.json({ error: "group_id and target_human_id are required" }, { status: 400 })
  if (currentHumanId === target_human_id) return NextResponse.json({ error: "Use the normal leave endpoint to leave a group" }, { status: 400 })
  
  const supabase = createServiceClient()

  // Verify requester is group owner or system admin
  const { data: member } = await supabase.from("group_members").select("role").eq("group_id", group_id).eq("human_id", currentHumanId).single()
  const { data: human } = await supabase.from("humans").select("role").eq("id", currentHumanId).single()

  if ((!member || member.role !== 'owner') && human?.role !== 'admin') {
      return NextResponse.json({ error: "Only group owners or admins can kick members." }, { status: 403 })
  }

  // Prevent kicking another owner unless requester is system admin
  const { data: targetMember } = await supabase.from("group_members").select("role").eq("group_id", group_id).eq("human_id", target_human_id).single()
  if (targetMember?.role === 'owner' && human?.role !== 'admin') {
      return NextResponse.json({ error: "Cannot kick another group owner." }, { status: 403 })
  }

  const { error } = await supabase
    .from("group_members")
    .delete()
    .eq("group_id", group_id)
    .eq("human_id", target_human_id)
    
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ success: true })
}
