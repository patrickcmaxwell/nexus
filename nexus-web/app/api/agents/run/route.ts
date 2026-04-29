export const maxDuration = 300 // 5 minutes — local dev has no limit anyway

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"
import OpenAI from "openai"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"
const BATCH_SIZE = 10 // conversations per LLM call
const MAX_MESSAGES_PER_CONVO = 80 // truncate long conversations

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

type Finding = {
  title: string
  description: string
  type: "idea" | "followup" | "opportunity" | "project" | "insight"
  priority: number
  source_conversation_title?: string
}

/**
 * POST /api/agents/run
 * Body: { agentId: string }
 *
 * Runs an agent's scan logic based on its capabilities and directives.
 * Only runs if the agent's status is 'active' or 'deployed'.
 */
export async function POST(req: NextRequest) {
  if (!await checkAuth()) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { agentId, forceFullScan } = await req.json()
  if (!agentId) {
    return NextResponse.json({ error: "agentId is required" }, { status: 400 })
  }

  const supabase = createServiceClient()

  // Load the agent
  const { data: agent } = await supabase
    .from("agents")
    .select("*")
    .eq("id", agentId)
    .eq("user_id", USER_ID)
    .single()

  if (!agent) {
    return NextResponse.json({ error: "Agent not found" }, { status: 404 })
  }

  // Only run if active or deployed
  if (!["active", "deployed"].includes(agent.status)) {
    return NextResponse.json({
      error: "Agent is not active. Set status to 'active' or 'deployed' to run.",
      status: agent.status,
    }, { status: 403 })
  }

  // Log scan start
  await supabase.from("agent_activity").insert({
    agent_id: agentId,
    user_id: USER_ID,
    action: "scan_started",
    details: { directives: agent.directives, capabilities: agent.capabilities },
  })

  const isFirstRun = forceFullScan ? true : !agent.last_scanned_at

  // ── Production: hand off to QStash and return immediately ──────────────────
  if (process.env.QSTASH_TOKEN) {
    const { Client: QStashClient } = await import("@upstash/qstash")
    const qstash = new QStashClient({ token: process.env.QSTASH_TOKEN })
    await qstash.publishJSON({
      url:     `${process.env.NEXT_PUBLIC_APP_URL}/api/agents/process`,
      body:    { agentId, cursor: 0, isFirstRun, totalFindings: 0, conversationsScanned: 0 },
      retries: 2,
    })
    return NextResponse.json({ queued: true, is_first_run: isFirstRun })
  }

  // ── Dev / local: run synchronously (no timeout concern) ────────────────────
  try {
    let conversationQuery = supabase
      .from("eve_conversations")
      .select("id, title, updated_at")
      .eq("user_id", USER_ID)
      .order("updated_at", { ascending: false })

    if (!isFirstRun && !forceFullScan) {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
      conversationQuery = conversationQuery.gte("updated_at", thirtyDaysAgo)
    }

    const { data: conversations } = await conversationQuery
    if (!conversations || conversations.length === 0) {
      await logActivity(supabase, agentId, "scan_completed", {
        message: "No conversations to scan",
        conversations_scanned: 0,
      })
      return NextResponse.json({ findings: 0, conversations_scanned: 0 })
    }

    const client = new OpenAI({
      apiKey: process.env.XAI_API_KEY!,
      baseURL: "https://api.x.ai/v1",
    })

    // Build the agent's analysis prompt
    const agentSystemPrompt = buildAgentPrompt(agent)

    let totalFindings = 0
    let conversationsScanned = 0

    // Process conversations in batches
    for (let i = 0; i < conversations.length; i += BATCH_SIZE) {
      const batch = conversations.slice(i, i + BATCH_SIZE)

      // Load messages for each conversation in this batch
      const batchContent = await Promise.all(
        batch.map(async (conv) => {
          const { data: messages } = await supabase
            .from("eve_history")
            .select("role, content, created_at")
            .eq("user_id", USER_ID)
            .eq("conversation_id", conv.id)
            .order("created_at", { ascending: true })
            .limit(MAX_MESSAGES_PER_CONVO)

          if (!messages || messages.length === 0) return null

          const transcript = messages
            .map((m) => `[${m.role === "user" ? "DIRECTOR" : "EVE"}]: ${m.content}`)
            .join("\n")

          return {
            conversationId: conv.id,
            title: conv.title,
            messageCount: messages.length,
            transcript,
          }
        })
      )

      const validConvos = batchContent.filter(Boolean) as NonNullable<typeof batchContent[0]>[]
      if (validConvos.length === 0) continue

      // Build the analysis request
      const analysisInput = validConvos
        .map((c, idx) => `--- CONVERSATION ${idx + 1}: "${c.title}" (${c.messageCount} messages) ---\n${c.transcript}\n--- END ---`)
        .join("\n\n")

      try {
        const response = await client.chat.completions.create({
          model: "grok-3-mini",
          messages: [
            { role: "system", content: agentSystemPrompt },
            { role: "user", content: analysisInput },
          ],
          max_tokens: 2048,
        })

        const raw = response.choices[0]?.message?.content ?? "[]"
        const match = raw.match(/\[[\s\S]*\]/)
        if (match) {
          const findings: Finding[] = JSON.parse(match[0])

          for (const finding of findings) {
            if (!finding.title || !finding.description) continue

            // Create or find an operation for this agent's findings
            const opName = `${agent.name} Findings`
            let { data: op } = await supabase
              .from("operations")
              .select("id")
              .eq("user_id", USER_ID)
              .ilike("name", opName)
              .maybeSingle()

            if (!op) {
              const { data: newOp } = await supabase
                .from("operations")
                .insert({
                  user_id: USER_ID,
                  name: opName,
                  description: `Autonomous findings from agent: ${agent.name}. ${agent.role}.`,
                  objectives: agent.directives,
                  status: "active",
                  priority: "medium",
                  directives: `Auto-populated by ${agent.name}`,
                })
                .select("id")
                .single()
              op = newOp
            }

            if (op) {
              // Add finding as a record
              await supabase.from("operation_records").insert({
                operation_id: op.id,
                user_id: USER_ID,
                title: finding.title,
                content: `${finding.description}\n\nPriority: ${finding.priority}/10\nType: ${finding.type}${finding.source_conversation_title ? `\nSource: "${finding.source_conversation_title}"` : ""}`,
                type: finding.type === "followup" ? "alert" : finding.type === "opportunity" ? "intel" : "finding",
                source: agent.name,
              })

              // Log each finding
              await logActivity(supabase, agentId, "finding_created", {
                title: finding.title,
                type: finding.type,
                priority: finding.priority,
                operation_id: op.id,
              })

              totalFindings++
            }
          }
        }
      } catch (err: any) {
        console.error(`[agent-runner] LLM error on batch ${i}:`, err.message)
        await logActivity(supabase, agentId, "error", {
          batch: i,
          error: err.message,
        })
      }

      conversationsScanned += validConvos.length

      // Log progress
      await logActivity(supabase, agentId, "batch_completed", {
        batch_index: Math.floor(i / BATCH_SIZE) + 1,
        conversations_in_batch: validConvos.length,
        findings_so_far: totalFindings,
      })
    }

    // Update agent with scan timestamp and total findings
    await supabase
      .from("agents")
      .update({
        last_scanned_at: new Date().toISOString(),
        total_findings: (agent.total_findings ?? 0) + totalFindings,
        updated_at: new Date().toISOString(),
      })
      .eq("id", agentId)

    // Log completion
    await logActivity(supabase, agentId, "scan_completed", {
      conversations_scanned: conversationsScanned,
      findings_created: totalFindings,
      is_first_run: isFirstRun,
    })

    return NextResponse.json({
      success: true,
      conversations_scanned: conversationsScanned,
      findings: totalFindings,
      is_first_run: isFirstRun,
    })
  } catch (err: any) {
    await logActivity(supabase, agentId, "error", { error: err.message })
    return NextResponse.json({ error: err.message }, { status: 500 })
  }
}

// GET — check run status / agent activity
export async function GET(req: NextRequest) {
  if (!await checkAuth()) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const agentId = req.nextUrl.searchParams.get("agentId")
  if (!agentId) {
    return NextResponse.json({ error: "agentId is required" }, { status: 400 })
  }

  const supabase = createServiceClient()
  const { data } = await supabase
    .from("agent_activity")
    .select("*")
    .eq("agent_id", agentId)
    .order("created_at", { ascending: false })
    .limit(50)

  return NextResponse.json({ activity: data ?? [] })
}

// ── Helpers ──────────────────────────────────────────────────────────────

async function logActivity(
  supabase: ReturnType<typeof createServiceClient>,
  agentId: string,
  action: string,
  details: Record<string, any>
) {
  await supabase.from("agent_activity").insert({
    agent_id: agentId,
    user_id: USER_ID,
    action,
    details,
  })
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
