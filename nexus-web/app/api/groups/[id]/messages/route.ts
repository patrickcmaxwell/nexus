import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { resolveHumanId } from "@/lib/desktop-auth"

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: groupId } = await params
  const humanId = await resolveHumanId(req)
  if (!humanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("group_messages")
    .select("id, content, created_at, human_id, humans(display_name, handle)")
    .eq("group_id", groupId)
    .order("created_at", { ascending: true })
    .limit(50)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ messages: data ?? [], currentHumanId: humanId })
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: groupId } = await params
  const humanId = await resolveHumanId(req)
  if (!humanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const { content } = await req.json()
  if (!content?.trim()) return NextResponse.json({ error: "content required" }, { status: 400 })

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("group_messages")
    .insert({ group_id: groupId, human_id: humanId, content: content.trim() })
    .select("id, content, created_at, human_id, humans(display_name, handle)")
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}
