import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { resolveHumanId } from "@/lib/desktop-auth"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

export async function POST(req: NextRequest) {
  const humanId = await resolveHumanId(req)
  if (!humanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })

  const { agentId, message, history = [] } = await req.json()
  if (!agentId || !message) return NextResponse.json({ error: "agentId and message are required" }, { status: 400 })

  const supabase = createServiceClient()
  const { data: agent } = await supabase
    .from("agents")
    .select("name, role, personality, directives, capabilities, status")
    .eq("id", agentId)
    .eq("user_id", USER_ID)
    .single()

  if (!agent) return NextResponse.json({ error: "Agent not found" }, { status: 404 })

  const systemPrompt = `You are ${agent.name}, an autonomous AI agent operating inside the Nexus command platform.

ROLE: ${agent.role}
PERSONALITY: ${agent.personality || "Professional, efficient, mission-focused."}
CAPABILITIES: ${(agent.capabilities ?? []).join(", ") || "General intelligence and analysis"}
STATUS: ${agent.status}

DIRECTIVES:
${agent.directives || "Operate in accordance with Nexus protocols."}

You are speaking directly with the Director (Patrick Maxwell), your commanding officer. Follow his instructions, provide status updates, and execute tasks within your capabilities. Be direct and concise. Address him as "Director" or "sir." When given a new task or directive, acknowledge it clearly and outline your approach.`

  const messages = [
    ...history.slice(-10).map((m: { role: string; content: string }) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    })),
    { role: "user" as const, content: message },
  ]

  // Try Grok first, fall back to Claude
  const response = await callGrok(systemPrompt, messages) ?? await callClaude(systemPrompt, messages)

  if (!response) return NextResponse.json({ error: "AI unavailable" }, { status: 503 })
  return NextResponse.json({ response })
}

async function callGrok(system: string, messages: { role: "user" | "assistant"; content: string }[]): Promise<string | null> {
  const key = process.env.XAI_API_KEY
  if (!key) return null
  try {
    const res = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: "grok-3-mini",
        messages: [{ role: "system", content: system }, ...messages],
        max_tokens: 400,
        temperature: 0.7,
      }),
    })
    if (!res.ok) return null
    const json = await res.json()
    return json.choices?.[0]?.message?.content ?? null
  } catch { return null }
}

async function callClaude(system: string, messages: { role: "user" | "assistant"; content: string }[]): Promise<string | null> {
  const key = process.env.ANTHROPIC_API_KEY
  if (!key) return null
  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 400,
        system,
        messages,
      }),
    })
    if (!res.ok) return null
    const json = await res.json()
    return json.content?.[0]?.text ?? null
  } catch { return null }
}
