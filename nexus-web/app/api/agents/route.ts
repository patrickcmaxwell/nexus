import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { resolveHumanId } from "@/lib/desktop-auth"

import { getActiveAuthId } from "@/lib/auth/session"

export async function GET(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const currentHumanId = await resolveHumanId(req)
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

export async function POST(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const currentHumanId = await resolveHumanId(req)
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
  await supabase.from("data_permissions").insert({
    resource_type: "agent",
    resource_id: data.id,
    owner_id: currentHumanId,
    visibility: visibility || "private",
  })
  return NextResponse.json(data)
}

export async function PATCH(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const currentHumanId = await resolveHumanId(req)
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

export async function DELETE(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const currentHumanId = await resolveHumanId(req)
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
