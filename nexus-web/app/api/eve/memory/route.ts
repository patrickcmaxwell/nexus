import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

// GET — fetch all active memories for system prompt injection
export async function GET(req: NextRequest) {
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const supabase = createServiceClient()
  const { data: memories } = await supabase
    .from("eve_memory")
    .select("id, type, content, priority, source, created_at, updated_at")
    .eq("user_id", USER_ID)
    .eq("is_active", true)
    .order("priority", { ascending: false })
    .order("updated_at", { ascending: false })
    .limit(50)

  return NextResponse.json({ memories: memories ?? [] })
}

// POST — save a new memory entry
export async function POST(req: NextRequest) {
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const { type, content, priority, source } = await req.json()
  if (!type || !content) return NextResponse.json({ error: "Missing type or content" }, { status: 400 })

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_memory")
    .insert({
      user_id: USER_ID,
      type: type ?? "fact",
      content,
      priority: priority ?? 5,
      source: source ?? "manual",
      is_active: true,
    })
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ memory: data })
}

// DELETE — deactivate a memory
export async function DELETE(req: NextRequest) {
  if (!await checkDesktopAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const { id } = await req.json()
  const supabase = createServiceClient()
  await supabase.from("eve_memory").update({ is_active: false }).eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ success: true })
}
