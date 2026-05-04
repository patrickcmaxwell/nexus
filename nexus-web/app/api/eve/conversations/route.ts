import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

async function checkAuth(req: NextRequest) {
  return checkDesktopAuth(req)
}

// GET — list all conversations, augmented with last-message preview + count
// so list UIs can render a meaningful row without opening the thread.
// Pass ?withPreviews=1 to include them (slightly heavier query). Default off
// for compatibility, on for ~most callers.
export async function GET(req: NextRequest) {
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { searchParams } = new URL(req.url)
  const withPreviews = searchParams.get("withPreviews") !== "0"  // default ON

  const { data, error } = await supabase
    .from("eve_conversations")
    .select("id, title, source, created_at, updated_at")
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
    .limit(500)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  type Conv = NonNullable<typeof data>[number]
  let conversations: Array<Conv & { preview?: string; message_count?: number }> = data ?? []

  if (withPreviews && conversations.length > 0) {
    // Latest assistant line per conversation in one query (window-free filter)
    const ids = conversations.map(c => c.id)
    const [previewRes, countRes] = await Promise.all([
      supabase
        .from("eve_history")
        .select("conversation_id, content, created_at, role")
        .eq("user_id", USER_ID)
        .eq("role", "assistant")
        .in("conversation_id", ids)
        .order("created_at", { ascending: false })
        .limit(2000),
      supabase
        .from("eve_history")
        .select("conversation_id")
        .eq("user_id", USER_ID)
        .in("conversation_id", ids),
    ])

    const previewByConv = new Map<string, string>()
    for (const row of previewRes.data ?? []) {
      if (!previewByConv.has(row.conversation_id)) {
        previewByConv.set(row.conversation_id, (row.content ?? "").slice(0, 220))
      }
    }
    const countByConv = new Map<string, number>()
    for (const row of countRes.data ?? []) {
      countByConv.set(row.conversation_id, (countByConv.get(row.conversation_id) ?? 0) + 1)
    }

    conversations = conversations.map(c => ({
      ...c,
      preview: previewByConv.get(c.id) ?? "",
      message_count: countByConv.get(c.id) ?? 0,
    }))
  }

  return NextResponse.json({ conversations })
}

// POST — create new conversation, returns id
export async function POST(req: NextRequest) {
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { title } = await req.json().catch(() => ({}))
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("eve_conversations")
    .insert({
      user_id: USER_ID,
      title: title ?? "New Session",
    })
    .select("id, title, created_at, updated_at")
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ conversation: data })
}

// PATCH — update conversation title
export async function PATCH(req: NextRequest) {
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id, title } = await req.json()
  if (!id || !title) return NextResponse.json({ error: "Missing id or title" }, { status: 400 })
  const supabase = createServiceClient()
  await supabase.from("eve_conversations").update({ title, updated_at: new Date().toISOString() }).eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ ok: true })
}

// DELETE — delete conversation and its messages
export async function DELETE(req: NextRequest) {
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "Missing id" }, { status: 400 })
  const supabase = createServiceClient()
  await supabase.from("eve_history").delete().eq("conversation_id", id).eq("user_id", USER_ID)
  await supabase.from("eve_conversations").delete().eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ ok: true })
}
