import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

import { getActiveAuthId } from "@/lib/auth/session"

// Sources used by smoke tests / curl QA loops. Conversations with these
// sources are real DB rows but they're test fixtures, not real chats — hide
// them from list UIs so the sidebar stays clean. Tests that want a hidden
// thread should use one of these source values, OR pass ?includeTests=1.
//
// Migration 018 introduces an `is_test` boolean for a structural fix; until
// it's applied this allowlist is the operative filter. Keep both in sync.
const TEST_SOURCES = ["qa-thread-test", "lumen-qa-fresh", "floating", "smoke-test", "test"] as const

async function checkAuth(req: NextRequest) {
  return checkDesktopAuth(req)
}

// GET — list all conversations, augmented with last-message preview + count
// so list UIs can render a meaningful row without opening the thread.
// Pass ?withPreviews=0 to skip previews. Pass ?includeTests=1 to include
// smoke-test conversations (default: hidden).
export async function GET(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()
  const { searchParams } = new URL(req.url)
  const withPreviews = searchParams.get("withPreviews") !== "0"  // default ON
  const includeTests = searchParams.get("includeTests") === "1"

  let query = supabase
    .from("eve_conversations")
    .select("id, title, source, created_at, updated_at")
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
    .limit(500)

  if (!includeTests) {
    query = query.not("source", "in", `(${TEST_SOURCES.join(",")})`)
  }

  const { data, error } = await query
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  type Conv = NonNullable<typeof data>[number]
  let conversations: Array<Conv & { preview?: string; message_count?: number }> = data ?? []

  if (withPreviews && conversations.length > 0) {
    const ids = conversations.map(c => c.id)

    // Per-conversation queries in parallel for both preview and count. A
    // single global `.limit(N)` query truncated long threads — a 446-msg
    // conversation showed message_count=0 and older threads got no preview.
    // Per-conversation is N round trips (~265 for current data) but each is
    // tiny, runs in parallel, and survives any data-volume growth.
    const [previewResults, countResults] = await Promise.all([
      Promise.all(
        ids.map(async (id) => {
          const { data } = await supabase
            .from("eve_history")
            .select("content")
            .eq("user_id", USER_ID)
            .eq("conversation_id", id)
            .eq("role", "assistant")
            .order("created_at", { ascending: false })
            .limit(1)
          return [id, (data?.[0]?.content ?? "").slice(0, 220)] as const
        })
      ),
      Promise.all(
        ids.map(async (id) => {
          const { count } = await supabase
            .from("eve_history")
            .select("*", { count: "exact", head: true })
            .eq("user_id", USER_ID)
            .eq("conversation_id", id)
          return [id, count ?? 0] as const
        })
      ),
    ])

    const previewByConv = new Map(previewResults)
    const countByConv = new Map(countResults)

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
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
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
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id, title } = await req.json()
  if (!id || !title) return NextResponse.json({ error: "Missing id or title" }, { status: 400 })
  const supabase = createServiceClient()
  await supabase.from("eve_conversations").update({ title, updated_at: new Date().toISOString() }).eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ ok: true })
}

// DELETE — delete conversation and its messages
export async function DELETE(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "Missing id" }, { status: 400 })
  const supabase = createServiceClient()
  await supabase.from("eve_history").delete().eq("conversation_id", id).eq("user_id", USER_ID)
  await supabase.from("eve_conversations").delete().eq("id", id).eq("user_id", USER_ID)
  return NextResponse.json({ ok: true })
}
