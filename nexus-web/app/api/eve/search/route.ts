import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { checkDesktopAuth } from "@/lib/desktop-auth"

import { getActiveAuthId } from "@/lib/auth/session"

// GET — cross-thread search. Matches conversation titles AND message content;
// returns one row per conversation with the conversation's title, an
// excerpt-style snippet, and a relevance hint. Powers Lumen + nexus-web's
// "search all threads" UI.
export async function GET(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const q = req.nextUrl.searchParams.get("q")
  if (!q || q.trim().length < 2) {
    return NextResponse.json({ results: [] })
  }

  const supabase = createServiceClient()

  const [{ data: titleMatches }, { data: contentMatches }] = await Promise.all([
    supabase
      .from("eve_conversations")
      .select("id, title, source, updated_at")
      .eq("user_id", USER_ID)
      .ilike("title", `%${q}%`)
      .order("updated_at", { ascending: false })
      .limit(50),
    supabase
      .from("eve_history")
      .select("id, conversation_id, content, role, created_at")
      .eq("user_id", USER_ID)
      .ilike("content", `%${q}%`)
      .order("created_at", { ascending: false })
      .limit(150),
  ])

  // Deduplicate by conversation_id, keeping title-match priority + most-recent
  // content snippet. Resolve titles for content-match conversations.
  type Result = {
    conversation_id: string
    title: string
    source: string
    snippet: string
    matchType: "title" | "content" | "both"
    role: string | null
    created_at: string | null
    updated_at: string | null
  }
  const byConv = new Map<string, Result>()

  for (const t of titleMatches ?? []) {
    byConv.set(t.id as string, {
      conversation_id: t.id as string,
      title: (t.title as string) ?? "Untitled",
      source: (t.source as string) ?? "unknown",
      snippet: "",
      matchType: "title",
      role: null,
      created_at: null,
      updated_at: t.updated_at as string,
    })
  }

  // Lookup titles for any content-match conversation we haven't seen yet
  const contentConvIds = Array.from(new Set((contentMatches ?? []).map(m => m.conversation_id as string)))
  const missingIds = contentConvIds.filter(id => !byConv.has(id))
  let titleById: Record<string, { title: string; source: string; updated_at: string }> = {}
  if (missingIds.length > 0) {
    const { data: convRows } = await supabase
      .from("eve_conversations")
      .select("id, title, source, updated_at")
      .eq("user_id", USER_ID)
      .in("id", missingIds)
    for (const c of convRows ?? []) {
      titleById[c.id as string] = {
        title: (c.title as string) ?? "Untitled",
        source: (c.source as string) ?? "unknown",
        updated_at: c.updated_at as string,
      }
    }
  }

  for (const m of contentMatches ?? []) {
    const convId = m.conversation_id as string
    const content = (m.content as string) ?? ""
    const idx = content.toLowerCase().indexOf(q.toLowerCase())
    const start = Math.max(0, idx - 40)
    const end = Math.min(content.length, idx + q.length + 80)
    const snippet =
      (start > 0 ? "…" : "") +
      content.slice(start, end).trim() +
      (end < content.length ? "…" : "")

    const existing = byConv.get(convId)
    if (existing) {
      // Title match plus content match — promote
      if (!existing.snippet) {
        existing.snippet = snippet
        existing.role = m.role as string
        existing.created_at = m.created_at as string
        existing.matchType = "both"
      }
    } else {
      const meta = titleById[convId]
      if (!meta) continue  // shouldn't happen
      byConv.set(convId, {
        conversation_id: convId,
        title: meta.title,
        source: meta.source,
        snippet,
        matchType: "content",
        role: m.role as string,
        created_at: m.created_at as string,
        updated_at: meta.updated_at,
      })
    }
  }

  // Sort: title matches first, then by most recent
  const results = Array.from(byConv.values()).sort((a, b) => {
    const aTitle = a.matchType === "title" || a.matchType === "both" ? 1 : 0
    const bTitle = b.matchType === "title" || b.matchType === "both" ? 1 : 0
    if (aTitle !== bTitle) return bTitle - aTitle
    return (b.updated_at ?? "").localeCompare(a.updated_at ?? "")
  })

  return NextResponse.json({ results })
}
