export const maxDuration = 60

import { NextRequest, NextResponse } from "next/server"
import { Receiver, Client as QStashClient } from "@upstash/qstash"
import { createServiceClient } from "@/lib/supabase/service"
import OpenAI from "openai"

import { getActiveAuthId } from "@/lib/auth/session"
const BATCH_SIZE = 10
const MAX_MESSAGES_PER_CONVO = 80

type JobPayload = {
  agentId: string
  cursor: number
  isFirstRun: boolean
  totalFindings: number
  conversationsScanned: number
}

type Finding = {
  title: string
  description: string
  type: "idea" | "followup" | "opportunity" | "project" | "insight"
  priority: number
  source_conversation_title?: string
}

/**
 * POST /api/agents/process
 * Called by QStash for each batch of an agent scan.
 * Processes BATCH_SIZE conversations, saves findings, then chains to the next batch.
 * Finalizes the agent record when no more conversations remain.
 */
export async function POST(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const body = await req.text()

  // Verify QStash signature when signing keys are present
  if (process.env.QSTASH_CURRENT_SIGNING_KEY) {
    const receiver = new Receiver({
      currentSigningKey: process.env.QSTASH_CURRENT_SIGNING_KEY,
      nextSigningKey:    process.env.QSTASH_NEXT_SIGNING_KEY ?? "",
    })
    const valid = await receiver.verify({
      signature: req.headers.get("upstash-signature") ?? "",
      body,
      clockTolerance: 5,
    }).catch(() => false)

    if (!valid) {
      return NextResponse.json({ error: "Invalid QStash signature" }, { status: 401 })
    }
  }

  const { agentId, cursor, isFirstRun, totalFindings: prevFindings, conversationsScanned: prevScanned }: JobPayload = JSON.parse(body)

  const supabase = createServiceClient()

  const { data: agent } = await supabase
    .from("agents")
    .select("*")
    .eq("id", agentId)
    .eq("user_id", USER_ID)
    .single()

  if (!agent) return NextResponse.json({ error: "Agent not found" }, { status: 404 })

  // Fetch one page of conversations
  let query = supabase
    .from("eve_conversations")
    .select("id, title, updated_at")
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
    .range(cursor, cursor + BATCH_SIZE - 1)

  if (!isFirstRun) {
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
    query = query.gte("updated_at", thirtyDaysAgo)
  }

  const { data: conversations } = await query

  // Nothing left — finalize
  if (!conversations || conversations.length === 0) {
    await finalize(supabase, agentId, USER_ID, agent, prevFindings, prevScanned, isFirstRun)
    return NextResponse.json({ done: true, conversations_scanned: prevScanned, findings: prevFindings })
  }

  // Load messages for each conversation in this batch
  const batchContent = await Promise.all(
    conversations.map(async (conv) => {
      const { data: messages } = await supabase
        .from("eve_history")
        .select("role, content, created_at")
        .eq("user_id", USER_ID)
        .eq("conversation_id", conv.id)
        .order("created_at", { ascending: true })
        .limit(MAX_MESSAGES_PER_CONVO)

      if (!messages || messages.length === 0) return null

      return {
        conversationId: conv.id,
        title: conv.title,
        messageCount: messages.length,
        transcript: messages
          .map((m) => `[${m.role === "user" ? "DIRECTOR" : "EVE"}]: ${m.content}`)
          .join("\n"),
      }
    })
  )

  const validConvos = batchContent.filter(Boolean) as NonNullable<(typeof batchContent)[0]>[]

  let batchFindings = 0

  if (validConvos.length > 0) {
    const client = new OpenAI({ apiKey: process.env.XAI_API_KEY!, baseURL: "https://api.x.ai/v1" })
    const analysisInput = validConvos
      .map((c, i) => `--- CONVERSATION ${i + 1}: "${c.title}" (${c.messageCount} messages) ---\n${c.transcript}\n--- END ---`)
      .join("\n\n")

    try {
      const response = await client.chat.completions.create({
        model: "grok-3-mini",
        messages: [
          { role: "system", content: buildAgentPrompt(agent) },
          { role: "user",   content: analysisInput },
        ],
        max_tokens: 2048,
      })

      const raw   = response.choices[0]?.message?.content ?? "[]"
      const match = raw.match(/\[[\s\S]*\]/)

      if (match) {
        const findings: Finding[] = JSON.parse(match[0])
        batchFindings = await saveFindings(supabase, agentId, USER_ID, agent, findings)
      }
    } catch (err: any) {
      await logActivity(supabase, agentId, USER_ID, "error", { cursor, error: err.message })
    }
  }

  const newTotalFindings  = prevFindings + batchFindings
  const newTotalScanned   = prevScanned  + validConvos.length
  const batchIndex        = Math.floor(cursor / BATCH_SIZE) + 1

  await logActivity(supabase, agentId, USER_ID, "batch_completed", {
    batch_index: batchIndex,
    conversations_in_batch: validConvos.length,
    findings_so_far: newTotalFindings,
  })

  // If we got a full page there may be more — chain to next batch
  if (conversations.length === BATCH_SIZE) {
    const qstash = new QStashClient({ token: process.env.QSTASH_TOKEN! })
    await qstash.publishJSON({
      url:     `${process.env.NEXT_PUBLIC_APP_URL}/api/agents/process`,
      body:    { agentId, cursor: cursor + BATCH_SIZE, isFirstRun, totalFindings: newTotalFindings, conversationsScanned: newTotalScanned } satisfies JobPayload,
      retries: 2,
    })
    return NextResponse.json({ batch_done: true, next_cursor: cursor + BATCH_SIZE, findings_so_far: newTotalFindings })
  }

  // Last batch — finalize
  await finalize(supabase, agentId, USER_ID, agent, newTotalFindings, newTotalScanned, isFirstRun)
  return NextResponse.json({ done: true, conversations_scanned: newTotalScanned, findings: newTotalFindings })
}

// ── Helpers ──────────────────────────────────────────────────────────────────

async function finalize(
  supabase: ReturnType<typeof createServiceClient>,
  agentId: string,
  userId: string,
  agent: any,
  totalFindings: number,
  conversationsScanned: number,
  isFirstRun: boolean,
) {
  await supabase
    .from("agents")
    .update({
      last_scanned_at: new Date().toISOString(),
      total_findings:  (agent.total_findings ?? 0) + totalFindings,
      updated_at:      new Date().toISOString(),
    })
    .eq("id", agentId)

  await logActivity(supabase, agentId, userId, "scan_completed", {
    conversations_scanned: conversationsScanned,
    findings_created:      totalFindings,
    is_first_run:          isFirstRun,
  })
}

async function saveFindings(
  supabase: ReturnType<typeof createServiceClient>,
  agentId: string,
  userId: string,
  agent: any,
  findings: Finding[],
): Promise<number> {
  let count = 0
  const opName = `${agent.name} Findings`

  for (const finding of findings) {
    if (!finding.title || !finding.description) continue

    let { data: op } = await supabase
      .from("operations")
      .select("id")
      .eq("user_id", userId)
      .ilike("name", opName)
      .maybeSingle()

    if (!op) {
      const { data: newOp } = await supabase
        .from("operations")
        .insert({
          user_id:     userId,
          name:        opName,
          description: `Autonomous findings from agent: ${agent.name}. ${agent.role}.`,
          objectives:  agent.directives,
          status:      "active",
          priority:    "medium",
          directives:  `Auto-populated by ${agent.name}`,
        })
        .select("id")
        .single()
      op = newOp
    }

    if (!op) continue

    await supabase.from("operation_records").insert({
      operation_id: op.id,
      user_id:      userId,
      title:        finding.title,
      content:      `${finding.description}\n\nPriority: ${finding.priority}/10\nType: ${finding.type}${finding.source_conversation_title ? `\nSource: "${finding.source_conversation_title}"` : ""}`,
      type:         finding.type === "followup" ? "alert" : finding.type === "opportunity" ? "intel" : "finding",
      source:       agent.name,
    })

    await logActivity(supabase, agentId, userId, "finding_created", {
      title:    finding.title,
      type:     finding.type,
      priority: finding.priority,
    })

    count++
  }

  return count
}

async function logActivity(
  supabase: ReturnType<typeof createServiceClient>,
  agentId: string,
  userId: string,
  action: string,
  details: Record<string, any>,
) {
  await supabase.from("agent_activity").insert({ agent_id: agentId, user_id: userId, action, details })
}

function buildAgentPrompt(agent: any): string {
  return `You are ${agent.name}, an autonomous AI agent operating inside the Nexus command platform.

ROLE: ${agent.role}
PERSONALITY: ${agent.personality}
CAPABILITIES: ${(agent.capabilities ?? []).join(", ")}

DIRECTIVES:
${agent.directives}

TASK:
Analyze the following conversations between the Director (Patrick Maxwell) and Eve (his AI). Based on your directives, extract actionable findings.

For each finding, return a JSON object with:
- title: Short, descriptive title (max 60 chars)
- description: 2-3 sentence explanation of the finding and why it matters
- type: One of "idea", "followup", "opportunity", "project", "insight"
- priority: 1-10 (10 = most important)
- source_conversation_title: The title of the conversation this came from

RULES:
1. Only extract findings that are genuinely interesting or actionable — no filler.
2. If a conversation has nothing relevant, skip it entirely.
3. Prioritize things the Director expressed interest in but hasn't acted on.
4. Look for patterns across conversations, not just individual mentions.
5. Be specific. "The Director mentioned wanting to build an app" is too vague. "The Director discussed building a collaboration tool called TalkCircles" is specific.

Return ONLY a JSON array of findings. If no findings, return [].`
}
