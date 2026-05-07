import { NextResponse } from "next/server"
import { cookies } from "next/headers"
import { createServiceClient } from "@/lib/supabase/service"

import { getActiveAuthId } from "@/lib/auth/session"

async function checkAuth() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return false
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("id, expires_at")
    .eq("id", sessionId)
    .single()
  if (!data) return false
  return new Date(data.expires_at) > new Date()
}

// POST — summarize unsummarized conversation history into long-term memory
export async function POST() {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth()) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  if (!process.env.XAI_API_KEY) return NextResponse.json({ error: "No XAI_API_KEY" }, { status: 500 })

  const supabase = createServiceClient()

  // Fetch unsummarized messages (oldest first, up to 60)
  const { data: rows } = await supabase
    .from("eve_history")
    .select("role, content, created_at")
    .eq("user_id", USER_ID)
    .eq("summarized", false)
    .order("created_at", { ascending: true })
    .limit(60)

  if (!rows || rows.length < 10) {
    return NextResponse.json({ skipped: true, reason: "Not enough messages to summarize" })
  }

  const transcript = rows
    .map((r) => `${r.role === "user" ? "USER" : "EVE"}: ${r.content}`)
    .join("\n")

  // Ask Grok to extract structured memory from this conversation
  const summaryRes = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${process.env.XAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: "grok-3-fast",
      messages: [
        {
          role: "system",
          content: `You are Eve, analyzing a conversation to extract persistent memory entries.
Extract ONLY items that should be remembered long-term: facts about the user, active tasks, ongoing objectives, important decisions, preferences, or project details.
Return ONLY valid JSON — an array of memory objects with this exact shape:
[{"type":"fact|task|objective|preference|project","content":"concise description","importance":1-10,"tags":["tag1","tag2"]}]
Be selective — only extract genuinely important, durable information. Skip pleasantries.`,
        },
        {
          role: "user",
          content: `Extract memories from this conversation:\n\n${transcript}`,
        },
      ],
      temperature: 0.2,
      max_tokens: 2048,
    }),
  })

  if (!summaryRes.ok) {
    return NextResponse.json({ error: "Grok summarization failed" }, { status: 500 })
  }

  const summaryJson = await summaryRes.json()
  const raw = summaryJson?.choices?.[0]?.message?.content ?? "[]"

  let memories: Array<{ type: string; content: string; importance: number; tags: string[] }> = []
  try {
    const match = raw.match(/\[[\s\S]*\]/)
    memories = match ? JSON.parse(match[0]) : []
  } catch {
    return NextResponse.json({ error: "Failed to parse memory JSON", raw }, { status: 500 })
  }

  // Save memories to memory bank using actual schema columns
  if (memories.length > 0) {
    await supabase.from("eve_memory").insert(
      memories.map((m) => ({
        user_id: USER_ID,
        type: m.type ?? "fact",
        content: m.content,
        priority: Math.min(10, Math.max(1, m.importance ?? 5)),
        source: "auto-summarize",
        is_active: true,
      }))
    )
  }

  // Mark these messages as summarized
  const { data: idRows } = await supabase
    .from("eve_history")
    .select("id")
    .eq("user_id", USER_ID)
    .eq("summarized", false)
    .order("created_at", { ascending: true })
    .limit(60)

  if (idRows && idRows.length > 0) {
    await supabase
      .from("eve_history")
      .update({ summarized: true })
      .in("id", idRows.map((r) => r.id))
  }

  return NextResponse.json({ success: true, memoriesExtracted: memories.length })
}
