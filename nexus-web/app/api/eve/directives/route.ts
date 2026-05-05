import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

import { getActiveAuthId } from "@/lib/auth/session"

export async function GET(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_directives")
    .select("*")
    .eq("user_id", USER_ID)
    .order("priority", { ascending: false })
    .order("created_at", { ascending: true })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ directives: data ?? [] })
}

export async function POST(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { type, title, content, priority = 0, target = "all" } = body
  if (!type || !title || !content) {
    return NextResponse.json({ error: "type, title, and content are required" }, { status: 400 })
  }
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_directives")
    .insert({ user_id: USER_ID, type, title, content, priority, target, is_active: true })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ directive: data })
}

export async function PATCH(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { id, ...updates } = body
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_directives")
    .update(updates)
    .eq("id", id)
    .eq("user_id", USER_ID)
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ directive: data })
}

export async function DELETE(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("eve_directives")
    .delete()
    .eq("id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
