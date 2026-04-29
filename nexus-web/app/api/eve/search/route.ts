import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"
import { createServiceClient } from "@/lib/supabase/service"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

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

// GET — search message content across all conversations
export async function GET(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const q = req.nextUrl.searchParams.get("q")
  if (!q || q.trim().length < 2) {
    return NextResponse.json({ results: [] })
  }

  const supabase = createServiceClient()

  // Search by title first
  const { data: titleMatches } = await supabase
    .from("eve_conversations")
    .select("id, title")
    .eq("user_id", USER_ID)
    .ilike("title", `%${q}%`)
    .limit(50)

  // Search message content using ilike
  const { data: contentMatches } = await supabase
    .from("eve_history")
    .select("id, conversation_id, content, role, created_at")
    .eq("user_id", USER_ID)
    .ilike("content", `%${q}%`)
    .order("created_at", { ascending: false })
    .limit(100)

  // Deduplicate by conversation_id and build snippets
  const seen = new Set<string>()
  const results: Array<{ conversation_id: string; snippet: string; role: string; created_at: string }> = []

  // Add title matches
  for (const t of titleMatches ?? []) {
    if (!seen.has(t.id)) {
      seen.add(t.id)
      results.push({
        conversation_id: t.id,
        snippet: `Title: ${t.title}`,
        role: "title",
        created_at: "",
      })
    }
  }

  // Add content matches with snippets
  for (const m of contentMatches ?? []) {
    if (!seen.has(m.conversation_id)) {
      seen.add(m.conversation_id)
      // Extract a snippet around the match
      const idx = m.content.toLowerCase().indexOf(q.toLowerCase())
      const start = Math.max(0, idx - 40)
      const end = Math.min(m.content.length, idx + q.length + 60)
      const snippet = (start > 0 ? "..." : "") + m.content.slice(start, end).trim() + (end < m.content.length ? "..." : "")
      results.push({
        conversation_id: m.conversation_id,
        snippet,
        role: m.role,
        created_at: m.created_at,
      })
    }
  }

  return NextResponse.json({ results })
}
