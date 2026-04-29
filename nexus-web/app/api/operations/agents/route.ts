import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"

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

// POST — assign an agent to an operation
export async function POST(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { operation_id, agent_id, role_in_op } = await req.json()
  if (!operation_id || !agent_id) return NextResponse.json({ error: "operation_id and agent_id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operation_agents")
    .insert({ operation_id, agent_id, role_in_op: role_in_op ?? null })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

// DELETE — remove an agent from an operation
export async function DELETE(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { operation_id, agent_id } = await req.json()
  if (!operation_id || !agent_id) return NextResponse.json({ error: "operation_id and agent_id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("operation_agents")
    .delete()
    .eq("operation_id", operation_id)
    .eq("agent_id", agent_id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
