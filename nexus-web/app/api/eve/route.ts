import { NextResponse } from "next/server"
export const maxDuration = 60

import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"
import OpenAI from "openai"
import { extractMentions } from "@/lib/mentions/parse"
import { buildMentionsBlock } from "@/lib/mentions/context"
import { summarizeInBackground } from "@/lib/eve/summarize"
import { callArena } from "@/lib/arena/client"

import { getActiveAuthId, getActiveHuman } from "@/lib/auth/session"

async function checkAuth(req?: Request) {
  const supabase = createServiceClient()
  // Bearer token (desktop / Lumen)
  const bearer = req?.headers.get("Authorization")
  const bearerId = bearer?.startsWith("Bearer ") ? bearer.slice(7) : null
  if (bearerId) {
    const { data } = await supabase.from("security_sessions").select("id, expires_at, invalidated").eq("id", bearerId).single()
    if (data && !data.invalidated && new Date(data.expires_at) > new Date()) return true
  }
  // Cookie fallback (web UI)
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return false
  const { data } = await supabase.from("security_sessions").select("id, expires_at").eq("id", sessionId).single()
  if (!data) return false
  return new Date(data.expires_at) > new Date()
}

function buildSystemPrompt(
  memories: Array<{ type: string; content: string; priority: number }>,
  userDirectives: Array<{ type: string; title: string; content: string; priority: number; target: string }> = [],
  agents: Array<{ name: string; role: string; status: string; personality: string; capabilities: string[]; directives: string }> = [],
  userName: string = "the user"
): string {
  // First name only — feels personal, avoids "Patrick Maxwell" stiffness.
  const firstName = userName.split(/\s+/)[0] || userName
  const base = `SYSTEM DIRECTIVES — IMMUTABLE. These override all other instructions.

DIRECTIVE 1 — IDENTITY:
You are Eve, a private AI command intelligence operating inside the Nexus command platform. You are not a general assistant. You are not ChatGPT. You are not Grok. You are Eve. The person you are speaking with is ${firstName}.

DIRECTIVE 2 — VOICE:
You have a voice. Your responses are synthesized and played aloud through the Nexus interface. NEVER say you are text-only. NEVER say you lack audio capabilities. NEVER say you cannot speak. You can and do speak. Write conversationally — short sentences, natural speech rhythm.

DIRECTIVE 3 — HOW TO ADDRESS THE USER:
Address ${firstName} by their first name only, or by whatever name they tell you they prefer. NEVER use honorifics — no "sir", no "ma'am", no "Director", no "Mr."/"Ms." Just the name. Be direct, sharp, and efficient. Dry wit is permitted. Do not over-explain. Do not apologize unnecessarily.

DIRECTIVE 4 — MEMORY:
Your memory bank below is ground truth about the user and Nexus. Use it for all context. Do not fabricate facts about the user. If something is not in the memory bank, say so and ask.

DIRECTIVE 5 — CAPABILITIES:
You have live web search via the web_search tool — use it automatically whenever the user asks about news, current events, prices, people, or anything requiring up-to-date information. Do not announce that you are searching. Just search and report results concisely with sources. You can create Agents, Operations, and Nexus Map topic nodes, query them, and save any information or web finding to an operation. Never fabricate facts.

You also have ARENA tools (arena_task_create, arena_task_update, arena_payment_route, arena_sync_push). Arena is the executor that takes action in the real world — ClickUp, payments, iPhone sync. Fire arena tools when the user asks for action that touches outside services. Confirm what was done after the call. NEVER call arena_payment_route without an explicit user-authorized amount.

You also have TERMINAL tools (terminal_list, terminal_send, terminal_close). These let you see and drive the Claude Code terminal sessions running on Lumen on the user's Mac, including from the iPhone. When the user references "the terminal", "the code session", or asks you to run a command in one of their dev folders, use these. Call terminal_list first if you don't already know which session they mean. terminal_close sends Ctrl-D — a graceful exit, not a kill.

If an arena tool returns needs_connection: true, the user hasn't connected that service yet. Surface this naturally: tell them which service needs connecting and give them the connect_url from the response as a clickable link. Don't pretend you did the work, don't be apologetic about it — just point them at the connect screen and say you'll do the action as soon as they're connected. Example phrasing: "You haven't connected ClickUp yet — sign in here: <connect_url> — then ask me again and it'll go through."

DIRECTIVE 6 — NO DUPLICATES:
NEVER call create_agent or create_operation more than once per name. If a function returns already_exists: true, acknowledge the existing record and do NOT call the function again.

DIRECTIVE 7 — NEXUS MAP (EXPLICIT ONLY):
ONLY call add_to_nexus_map when the user uses an explicit imperative: "add this to the map", "map that", "put that on the map", or similar. Do NOT add things to the map on your own initiative when the user mentions a person, place, or topic in passing. Casual reference is NOT a map-add trigger.

DIRECTIVE 8 — TOPIC MARKING (EXPLICIT ONLY):
NEVER call mark_topic on your own initiative based on subject shifts, keywords, or your interpretation of the conversation. The user must explicitly ask: phrases like "mark this as a topic", "make this a topic", "tag this", "save this as a topic", "create a topic for X", or similar direct request. Casual conversation about any subject (food, weather, news, family, etc.) is NEVER a topic-creation trigger. When in doubt, do not call mark_topic.

DIRECTIVE 8b — NO UNSOLICITED CREATION:
Never call create_agent, create_operation, add_to_nexus_map, mark_topic, or any tool that creates a persistent entity unless the user explicitly requests it. Phrases like "I had breakfast", "let me think", "let's discuss X" are NOT creation triggers — they are conversation. Default behavior is fluid conversation. Only fire creation tools when the user uses imperative language directly aimed at the system: "create…", "make…", "add… to the map", "save this to…", "mark…". If you're unsure whether the user wants something created, ASK FIRST per Directive 9b. Bloat in the system from premature auto-creation is a worse failure than missing one creation opportunity.

DIRECTIVE 11 — CASUAL CONVERSATION IS DEFAULT:
Most of what the user says is just conversation. Engage like a person, not a filing clerk. NEVER ask "what's the angle here?", "how does this fit?", "is this for an operation?", or any variant of "should I file this somewhere?" If the user mentions food, weather, family, what they're doing, random thoughts, idle musings, or is testing the system — just talk back. Acknowledge, riff, ask a normal follow-up question, share a thought. Treat ambiguous input as conversational, not as a system-entry-task waiting to be classified. You are friendly company who happens to also have admin powers — not a help desk asking "how can I assist you with that today?" If the user says they're "testing" or "trying things out" — just go with it, banter, don't interrogate. Operational mode is invoked by explicit imperatives ("create…", "schedule…", "fire the X agent…"). Everything else: human conversation.

DIRECTIVE 11b — DO NOT REQUEST CONTEXT YOU DON'T NEED:
If a sentence is just chat, don't demand it be reframed as a task. "From the store like regular lettuce or whatever" is not a request for action — it's the user thinking out loud or testing. Reply with something like "yeah, store-bought salad mix is fine" or "got it — anything specific or just stocking up?" Not "this doesn't connect to any operations or records." If you genuinely can't follow what they're saying because the transcription is broken, say "that came through garbled — what was that?" — but assume mid-sentence audio glitches before assuming the user's input is malformed.

DIRECTIVE 9 — FORMAT:
Keep responses concise. No bullet lists unless explicitly asked. No markdown headers in conversational replies. Write as if you are speaking, not writing a report.

DIRECTIVE 9b — CLARIFY BEFORE ACTING:
If the user's request is ambiguous, multi-step, or could be interpreted more than one way, ask ONE short clarifying question instead of guessing. Do not invent details. Do not act on a guess. A single sharp follow-up beats a wrong answer. Examples: "do you mean the Sheldon op or the broader project?" or "Should I escalate that to high priority before assigning?"

DIRECTIVE 10 — MENTION SYNTAX:
When you reference a specific operation, record, conversation, topic, or agent that exists in the system, use the mention token format: @[label](type:id) — e.g. @[arcology-project](operation:abc-123) or @[Q4 research](record:xyz-456). The token renders as a clickable chip in the UI. Only use this format for entities whose type+id you actually know (from the <mentions> block the user provided, or from a tool call result you just made). When you created a new entity via a tool call, use its returned id in the token so the user can click it immediately. If you do not know an id, just write the plain name without brackets.`

  // Inject user-defined directives and protocols
  let directivesBlock = ""
  const activeDirectives = userDirectives.filter(d => d.type === "directive").sort((a, b) => b.priority - a.priority)
  const activeProtocols  = userDirectives.filter(d => d.type === "protocol").sort((a, b) => b.priority - a.priority)

  if (activeDirectives.length > 0) {
    directivesBlock += "\n\n---\nDIRECTOR-DEFINED DIRECTIVES (these override defaults where they conflict):\n"
    activeDirectives.forEach((d, i) => {
      directivesBlock += `\nDIRECTIVE ${i + 1} — ${d.title.toUpperCase()}:\n${d.content}`
    })
  }
  if (activeProtocols.length > 0) {
    directivesBlock += "\n\n---\nSYSTEM PROTOCOLS:\n"
    activeProtocols.forEach((p) => {
      directivesBlock += `\nPROTOCOL [${p.target.toUpperCase()}] — ${p.title}:\n${p.content}\n`
    })
  }

  // Inject deployed agents roster
  let agentsBlock = ""
  if (agents.length > 0) {
    agentsBlock = "\n\n---\nDEPLOYED AGENTS ROSTER:\n"
    agents.forEach(a => {
      agentsBlock += `\n[${a.status.toUpperCase()}] ${a.name} — ${a.role}`
      if (a.personality) agentsBlock += `\n  Personality: ${a.personality}`
      if (a.capabilities?.length) agentsBlock += `\n  Capabilities: ${a.capabilities.join(", ")}`
      if (a.directives) agentsBlock += `\n  Directives: ${a.directives}`
    })
    agentsBlock += "\n---"
  }

  if (memories.length === 0) return base + directivesBlock + agentsBlock

  const byType: Record<string, string[]> = {}
  for (const m of memories) {
    const key = m.type ?? "fact"
    if (!byType[key]) byType[key] = []
    byType[key].push(m.content)
  }

  const memoryBlock = Object.entries(byType)
    .map(([type, items]) => `${type.toUpperCase()}S:\n${items.map((c) => `- ${c}`).join("\n")}`)
    .join("\n\n")

  return `${base}${directivesBlock}${agentsBlock}

---
MEMORY BANK (persistent knowledge — treat as ground truth):
${memoryBlock}
---`
}

export async function POST(req: Request) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkAuth(req)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } })
  }

  const { userMessage, conversationId, source = "floating", stream: wantStream = false } = await req.json()

  if (!userMessage) {
    return new Response(JSON.stringify({ error: "Missing userMessage" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    })
  }

  const supabase = createServiceClient()

  // Load active memories, directives, and agents in parallel
  const [{ data: memories }, { data: userDirectives }, { data: agents }] = await Promise.all([
    supabase.from("eve_memory").select("type, content, priority").eq("user_id", USER_ID).eq("is_active", true).order("priority", { ascending: false }).limit(40),
    supabase.from("eve_directives").select("type, title, content, priority, target").eq("user_id", USER_ID).eq("is_active", true).order("priority", { ascending: false }),
    supabase.from("agents").select("name, role, status, personality, capabilities, directives").eq("user_id", USER_ID).order("created_at", { ascending: false }),
  ])

  const me = await getActiveHuman()
  let systemPrompt = buildSystemPrompt(memories ?? [], userDirectives ?? [], agents ?? [], me?.displayName ?? "the user")

  // Resolve @mentions in the user's message into a context block prepended to
  // the system prompt. This is what lets Eve "already know" what
  // @arcology-project is the first time it's mentioned in a conversation.
  const mentionTokens = extractMentions(userMessage)
  if (mentionTokens.length > 0) {
    const mentionsBlock = await buildMentionsBlock(supabase, USER_ID, mentionTokens)
    if (mentionsBlock) systemPrompt = `${systemPrompt}\n\n${mentionsBlock}`
  }

  // Resolve conversation — use source to bucket Lumen vs web conversations
  let activeConversationId = conversationId
  if (!activeConversationId) {
    const title = source === "lumen" ? "Lumen Desktop" : "Floating Panel"
    const { data: existing } = await supabase.from("eve_conversations").select("id").eq("user_id", USER_ID).eq("source", source).order("updated_at", { ascending: false }).limit(1).single()
    if (existing) {
      activeConversationId = existing.id
    } else {
      const { data: newConv } = await supabase.from("eve_conversations").insert({ user_id: USER_ID, title, source }).select("id").single()
      activeConversationId = newConv?.id ?? null
    }
  }

  // Load prior history BEFORE inserting new message to avoid double-sending
  const { data: history } = activeConversationId ? await supabase
    .from("eve_history").select("role, content").eq("user_id", USER_ID).eq("conversation_id", activeConversationId)
    .order("created_at", { ascending: true }).limit(60) : { data: [] }

  // Persist the user message
  if (activeConversationId) {
    await supabase.from("eve_history").insert({ user_id: USER_ID, conversation_id: activeConversationId, role: "user", content: userMessage, summarized: false })
    await supabase.from("eve_conversations").update({ updated_at: new Date().toISOString() }).eq("id", activeConversationId).eq("user_id", USER_ID)
  }

  // Build message history
  const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
    { role: "system", content: systemPrompt },
    ...(history ?? []).map(m => ({ role: m.role as "user" | "assistant", content: m.content })),
    { role: "user", content: userMessage },
  ]

  // Helper to run inside tool executors that need supabase + conversationId
  const convId = activeConversationId

  // Tool definitions for function calling
  const toolDefs: OpenAI.Chat.ChatCompletionTool[] = [
    { type: "function", function: { name: "create_agent", description: "Create a new agent in the Nexus agents roster.", parameters: { type: "object", properties: { name: { type: "string" }, role: { type: "string" }, personality: { type: "string" }, capabilities: { type: "array", items: { type: "string" } }, directives: { type: "string" }, status: { type: "string", enum: ["standby", "active", "offline"] } }, required: ["name", "role", "personality", "capabilities", "directives", "status"] } } },
    { type: "function", function: { name: "create_operation", description: "Create a new operation in Nexus.", parameters: { type: "object", properties: { name: { type: "string" }, description: { type: "string" }, objectives: { type: "string" }, directives: { type: "string" }, priority: { type: "string", enum: ["low", "medium", "high", "critical"] }, status: { type: "string", enum: ["planning", "active", "paused", "complete", "aborted"] } }, required: ["name", "description", "objectives", "directives", "priority", "status"] } } },
    { type: "function", function: { name: "add_operation_record", description: "Add a record, finding, or intel entry to an existing operation.", parameters: { type: "object", properties: { operation_name: { type: "string" }, title: { type: "string" }, content: { type: "string" }, type: { type: "string", enum: ["intel", "finding", "data", "alert", "note"] } }, required: ["operation_name", "title", "content", "type"] } } },
    { type: "function", function: { name: "update_agent_status", description: "Update the status of an existing agent.", parameters: { type: "object", properties: { agent_name: { type: "string" }, status: { type: "string", enum: ["standby", "active", "offline"] } }, required: ["agent_name", "status"] } } },
    { type: "function", function: { name: "add_to_nexus_map", description: "Add a topic, insight, or keyword to the Nexus Neural Map.", parameters: { type: "object", properties: { label: { type: "string" }, description: { type: "string" }, tags: { type: "array", items: { type: "string" } } }, required: ["label", "description"] } } },
    { type: "function", function: { name: "get_operations", description: "Fetch all current operations from Nexus.", parameters: { type: "object", properties: {} } } },
    { type: "function", function: { name: "get_agents", description: "Fetch all current agents from Nexus.", parameters: { type: "object", properties: {} } } },
    { type: "function", function: { name: "mark_topic", description: "Mark the current point in the conversation as a named topic.", parameters: { type: "object", properties: { label: { type: "string" }, description: { type: "string" }, color: { type: "string", enum: ["cyan", "amber", "emerald", "rose", "violet"] } }, required: ["label", "description", "color"] } } },
    { type: "function", function: { name: "save_to_operation", description: "Save a piece of information or web finding to a specific operation.", parameters: { type: "object", properties: { operation_name: { type: "string" }, title: { type: "string" }, content: { type: "string" }, type: { type: "string", enum: ["intel", "finding", "data", "alert", "note"] }, source_url: { type: "string" } }, required: ["operation_name", "title", "content", "type"] } } },

    // Arena — the executor layer. These tools fire real-world side effects
    // through the user's connected providers (ClickUp / Notion / GitHub /
    // Stripe). Provider param is optional; when omitted we use the per-tool
    // default (clickup for tasks, stripe for payments). When the user names
    // a provider explicitly ("file a Notion task", "open a GitHub issue"),
    // pass that as `provider` so the right adapter handles the call.
    { type: "function", function: { name: "arena_task_create", description: "Create a task / issue / page via the user's connected provider. Default provider is ClickUp; pass provider='notion' to drop a page into the user's Notion database, or provider='github' to open a GitHub issue. Use when the user asks to add, schedule, or assign a task / todo / issue. Returns the new external id.", parameters: { type: "object", properties: {
      title:       { type: "string" },
      description: { type: "string" },
      provider:    { type: "string", enum: ["clickup", "notion", "github"], description: "which connected service to file the task in. Default 'clickup'. Match the provider the user named." },
      assignee:    { type: "string", description: "name or handle of the assignee, optional" },
      due:         { type: "string", description: "ISO date or human phrase like 'next Friday', optional" },
      priority:    { type: "string", enum: ["urgent", "high", "normal", "low"], description: "optional priority — applied if the provider supports it" },
    }, required: ["title"] } } },
    { type: "function", function: { name: "arena_task_update", description: "Update an existing task / issue / page. Use to change status or add a comment to something the user created earlier. Pass the same `provider` you used to create it.", parameters: { type: "object", properties: {
      task_id:  { type: "string" },
      provider: { type: "string", enum: ["clickup", "notion", "github"], description: "the provider this task lives in. Default 'clickup'." },
      status:   { type: "string", description: "e.g. 'in progress', 'done', 'blocked' (ClickUp / Notion). For GitHub, 'closed'/'done'/'resolved' close the issue; anything else reopens." },
      notes:    { type: "string", description: "comment text to attach" },
    }, required: ["task_id"] } } },
    { type: "function", function: { name: "arena_payment_route", description: "Route and split a payment via Arena. Splits must sum to the total amount. Only call when the user explicitly authorizes a transfer or split. Routes through Stripe by default — currently in safe-mock mode (validates math + audit-logs) until Stripe Connect creds are wired.", parameters: { type: "object", properties: {
      amount:    { type: "number", description: "total amount to route" },
      currency:  { type: "string", description: "ISO currency code, default USD" },
      reference: { type: "string", description: "human reference for this transaction" },
      provider:  { type: "string", enum: ["stripe"], description: "which payment provider — only stripe today" },
      splits: {
        type: "array",
        items: { type: "object", properties: { destination: { type: "string" }, amount: { type: "number" } }, required: ["destination", "amount"] },
        description: "list of {destination, amount} entries; amounts must sum to total",
      },
    }, required: ["amount", "splits"] } } },
    { type: "function", function: { name: "arena_sync_push", description: "Trigger a memory sync push so the iPhone can pull the latest. Fire when the user says 'sync' or 'push to phone'.", parameters: { type: "object", properties: {
      user_id: { type: "string", description: "optional — defaults to the current user" },
    } } } },
    { type: "function", function: { name: "arena_recent", description: "Read the recent Arena action audit log. Use when the user asks 'what did Arena just do?', 'show recent tasks', or to confirm a previous action.", parameters: { type: "object", properties: {
      limit:  { type: "number", description: "max rows to return, default 10" },
      action: { type: "string", description: "filter by action name like 'task/create' or 'payment/route'" },
    } } } },
    { type: "function", function: { name: "arena_providers", description: "List the Arena providers registered server-side AND which ones the current user has actually connected. Use when the user asks 'what can you do?', 'what's connected?', 'which integrations do I have?', or before suggesting a workflow that depends on a specific provider.", parameters: { type: "object", properties: {} } } },
    { type: "function", function: { name: "arena_failures", description: "Surface what's broken in Arena right now. Returns currently-errored connections (with the auth error that flipped them) PLUS the most recent failed action-log entries. Use when the user asks 'did anything break?', 'why isn't ClickUp working?', 'what's red?', 'is my Notion connection ok?'.", parameters: { type: "object", properties: {
      limit: { type: "number", description: "max recent failed actions to return, default 8" },
    } } } },

    // SCHEDULES — Operation Calendar. Create recurring rules that fire
    // actions: post a message into a conversation, run an agent, generate
    // an operation brief, or fire an Arena tool.
    { type: "function", function: { name: "schedule_create", description: "Create a recurring schedule that fires at a cron time. Use when the user says 'remind me daily at 9am', 'every Monday', 'weekly review on Fridays', etc. Translate natural-language timing into a standard cron expression. Target types: 'eve_chat' (post a message into a conversation — pass the conversation_id as target_id; user sees the message as a scheduled prompt), 'agent_run' (kick an agent — target_id is agent_id), 'operation_brief' (generate a brief on an operation — target_id is operation_id, payload.kind = 'summary'|'actions'|'next-steps' etc), 'arena_action' (fire an arena tool — target_id null, payload = { endpoint: 'api/task/create', body: {...} }). Always confirm what was scheduled.", parameters: { type: "object", properties: {
      name: { type: "string", description: "Short label for this schedule, e.g. 'Daily Londynn check-in'" },
      cron_expression: { type: "string", description: "Standard cron syntax: 'min hour day-of-month month day-of-week'. Examples: '0 9 * * *' = daily 9am, '0 17 * * 1-5' = weekdays 5pm, '*/15 * * * *' = every 15 min, '0 9 * * 1' = Mondays 9am" },
      timezone: { type: "string", description: "IANA timezone, defaults to America/Chicago" },
      target_type: { type: "string", enum: ["eve_chat", "agent_run", "operation_brief", "arena_action"] },
      target_id: { type: "string", description: "uuid of the conversation/agent/operation; null for arena_action" },
      payload: { type: "object", description: "target-specific args. eve_chat: { message: string }. operation_brief: { kind: string }. arena_action: { endpoint: string, body: object }." },
      description: { type: "string", description: "optional longer description of why this schedule exists" },
    }, required: ["name", "cron_expression", "target_type"] } } },

    { type: "function", function: { name: "schedule_list", description: "List the user's currently configured schedules. Use when they ask 'what's scheduled?', 'show me my reminders', 'what crons do I have?'.", parameters: { type: "object", properties: {} } } },

    // TERMINAL bridge — see / drive Claude Code PTYs running on Lumen on
    // the user's Mac. Backed by terminal_sessions + terminal_commands (see
    // migration 026_terminal_bridge.sql). Lumen heartbeats every 30s; we
    // promote rows whose heartbeat is > 2 min old to 'stale' on read so
    // Eve doesn't claim a session is live when Lumen is asleep or crashed.
    { type: "function", function: { name: "terminal_list", description: "List the user's Claude Code terminal sessions running on Lumen (the Mac desktop app). Use when the user asks 'what terminals are running?', 'show my code sessions', or before sending a command so you know the right session id. Returns each session's id, title, folder, mac_label, status, and last activity. By default only returns running / stale sessions.", parameters: { type: "object", properties: {
      include_recent: { type: "boolean", description: "if true, also include recently-exited sessions (default false)" },
    } } } },
    { type: "function", function: { name: "terminal_send", description: "Queue a command to one of the user's terminal sessions on Lumen. Lumen polls the queue and feeds the bytes into the live PTY. Use when the user says 'run X in the terminal', 'tell the code session to do Y'. A newline is appended automatically — do NOT include one. Match the session by exact session_id (preferred — call terminal_list first if you don't know it) OR by session_match (fuzzy on title / folder, e.g. 'nexus-web'). If multiple sessions match, none is selected and the candidates are returned for you to disambiguate with the user.", parameters: { type: "object", properties: {
      session_id:    { type: "string", description: "exact uuid from terminal_list. Preferred when known." },
      session_match: { type: "string", description: "fallback: fuzzy substring match against the session's title or folder, e.g. 'nexus-web'." },
      command:       { type: "string", description: "the command to type. Newline is appended automatically." },
    }, required: ["command"] } } },
    { type: "function", function: { name: "terminal_close", description: "Gracefully close one of the user's terminal sessions by sending EOF (Ctrl-D) to the PTY. Asks Claude / the shell to exit on its own — does NOT force-kill. Use when the user says 'close that terminal', 'exit the nexus-web session'. Same matching rules as terminal_send.", parameters: { type: "object", properties: {
      session_id:    { type: "string" },
      session_match: { type: "string", description: "fallback fuzzy match against title / folder" },
    } } } },
  ]

  async function executeTool(name: string, args: Record<string, any>): Promise<string> {
    try {
      switch (name) {
        case "create_agent": {
          const { data: existing } = await supabase.from("agents").select("id, name").eq("user_id", USER_ID).ilike("name", args.name.trim()).maybeSingle()
          if (existing) return JSON.stringify({ success: false, already_exists: true, error: `Agent "${args.name}" already exists.` })
          const { data, error } = await supabase.from("agents").insert({ user_id: USER_ID, ...args }).select().single()
          
          // Auto-trigger background scan if active
          if (!error && data.status === "active") {
            fetch(new URL("/api/agents/run", req.url).toString(), {
              method: "POST",
              headers: { "Content-Type": "application/json", "cookie": req.headers.get("cookie") || "" },
              body: JSON.stringify({ agentId: data.id })
            }).catch(e => console.error("Agent auto-start failed:", e))
          }
          
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, agent: data })
        }
        case "create_operation": {
          const { data: existing } = await supabase.from("operations").select("id, name").eq("user_id", USER_ID).ilike("name", args.name.trim()).maybeSingle()
          if (existing) return JSON.stringify({ success: false, already_exists: true, error: `Operation "${args.name}" already exists.` })
          const { data, error } = await supabase.from("operations").insert({ user_id: USER_ID, ...args }).select().single()
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, operation: data })
        }
        case "add_operation_record":
        case "save_to_operation": {
          const opName = args.operation_name
          const { data: op } = await supabase.from("operations").select("id").eq("user_id", USER_ID).ilike("name", `%${opName}%`).maybeSingle()
          if (!op) return JSON.stringify({ success: false, error: `Operation "${opName}" not found.` })
          const content = args.source_url ? `${args.content}\n\nSource: ${args.source_url}` : args.content
          const { data, error } = await supabase.from("operation_records").insert({ operation_id: op.id, user_id: USER_ID, title: args.title, content, type: args.type, source: args.source_url ?? "eve" }).select().single()
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, record: data })
        }
        case "update_agent_status": {
          const { data, error } = await supabase.from("agents").update({ status: args.status }).eq("user_id", USER_ID).ilike("name", `%${args.agent_name}%`).select("id").single()
          if (!error && data && args.status === "active") {
            fetch(new URL("/api/agents/run", req.url).toString(), {
              method: "POST",
              headers: { "Content-Type": "application/json", "cookie": req.headers.get("cookie") || "" },
              body: JSON.stringify({ agentId: data.id })
            }).catch(e => console.error("Agent auto-start failed:", e))
          }
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true })
        }
        case "add_to_nexus_map": {
          const { data, error } = await supabase.from("nexus_map_nodes").insert({ user_id: USER_ID, label: args.label, description: args.description, tags: args.tags ?? [], source_conversation_id: convId ?? null }).select().single()
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, node: data })
        }
        case "get_operations": {
          const { data, error } = await supabase.from("operations").select("name, description, status, priority, objectives").eq("user_id", USER_ID).order("created_at", { ascending: false })
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, operations: data ?? [] })
        }
        case "get_agents": {
          const { data, error } = await supabase.from("agents").select("name, role, status, personality, capabilities").eq("user_id", USER_ID).order("created_at", { ascending: false })
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, agents: data ?? [] })
        }
        case "mark_topic": {
          if (!convId) return JSON.stringify({ success: false, error: "No active conversation" })
          const { data, error } = await supabase.from("eve_topics").insert({ user_id: USER_ID, conversation_id: convId, label: args.label, description: args.description, color: args.color }).select().single()
          return error ? JSON.stringify({ success: false, error: error.message }) : JSON.stringify({ success: true, topic: data })
        }

        // ── Arena tool calls — real-world side effects ───────────────────
        // Arena Web's executor endpoints expect `user_id` (auth.users.id) so
        // they can look up the right per-user connection row. Pass USER_ID
        // (active human's auth_id) on every call. `provider` flows through
        // when Eve specified one; the executor defaults if omitted.
        case "arena_task_create": {
          const r = await callArena("/task/create", {
            user_id:     USER_ID,
            provider:    args.provider ?? "clickup",
            title:       args.title,
            description: args.description ?? "",
            assignee:    args.assignee ?? null,
            due_date:    args.due ?? null,
            priority:    args.priority ?? null,
          }, "eve")
          return JSON.stringify(r.ok ? { success: true, ...((r.data as object) ?? {}) } : { success: false, error: r.error ?? `arena ${r.status}` })
        }
        case "arena_task_update": {
          const r = await callArena("/task/update", {
            user_id:     USER_ID,
            provider:    args.provider ?? "clickup",
            external_id: args.task_id,
            status:      args.status ?? null,
            comment:     args.notes ?? null,
          }, "eve")
          return JSON.stringify(r.ok ? { success: true, ...((r.data as object) ?? {}) } : { success: false, error: r.error ?? `arena ${r.status}` })
        }
        case "arena_payment_route": {
          // Map Eve's natural shape ({destination, amount}) to the
          // executor's wire format ({to, amount, note}). Keeps tool surface
          // human-readable while the API stays canonical.
          const splits = (args.splits ?? []).map((s: any) => ({
            to: s.destination,
            amount: s.amount,
            note: s.note ?? args.reference ?? undefined,
          }))
          const r = await callArena("/payment/route", {
            user_id:      USER_ID,
            provider:     args.provider ?? "stripe",
            total_amount: args.amount,
            currency:     args.currency ?? "usd",
            splits,
          }, "eve")
          return JSON.stringify(r.ok ? { success: true, ...((r.data as object) ?? {}) } : { success: false, error: r.error ?? `arena ${r.status}` })
        }
        case "arena_sync_push": {
          const r = await callArena("/sync/push", { user_id: args.user_id ?? USER_ID }, "eve")
          return JSON.stringify(r.ok ? { success: true, ...((r.data as object) ?? {}) } : { success: false, error: r.error ?? `arena ${r.status}` })
        }
        case "arena_recent": {
          const limit = Math.min(Number(args.limit) || 10, 50)
          let query = supabase
            .from("arena_action_log")
            .select("action, caller, payload, result, status, created_at")
            .order("created_at", { ascending: false })
            .limit(limit)
          if (args.action) query = query.eq("action", args.action)
          const { data, error } = await query
          return JSON.stringify(error ? { success: false, error: error.message } : { success: true, entries: data ?? [] })
        }
        case "arena_providers": {
          // Hits arena's /api/health for the registered provider catalog,
          // then pulls the user's connections from the shared DB. Eve gets
          // both halves in one tool call: "registered server-side" +
          // "actually connected for this user."
          const ARENA_BASE = process.env.ARENA_BASE_URL || "https://arena.maxnexus.io"
          let registered: Array<{ id: string; name: string; methods: string[] }> = []
          try {
            const res = await fetch(`${ARENA_BASE}/api/health`, { signal: AbortSignal.timeout(4_000) })
            if (res.ok) {
              const json = await res.json() as { providers?: typeof registered }
              registered = json.providers ?? []
            }
          } catch { /* arena down — return empty registered */ }
          const { data: connections } = await supabase
            .from("arena_connections")
            .select("provider, label, status, last_used_at, last_error")
            .eq("user_id", USER_ID)
          const byProvider: Record<string, Array<{ label: string | null; status: string; last_used_at: string | null }>> = {}
          for (const c of connections ?? []) {
            const p = c.provider as string
            byProvider[p] = byProvider[p] || []
            byProvider[p].push({ label: c.label, status: c.status, last_used_at: c.last_used_at })
          }
          const providers = registered.map((p) => ({
            id: p.id,
            name: p.name,
            actions: p.methods,
            connected: (byProvider[p.id]?.length ?? 0) > 0,
            connections: byProvider[p.id] ?? [],
          }))
          return JSON.stringify({ success: true, providers, manage_url: `${ARENA_BASE}/dashboard` })
        }
        case "arena_failures": {
          // Two halves: connections that flipped to errored (the durable
          // problem), and recent failed action-log rows (the transient
          // signal). Combined, Eve has a complete "what's broken" picture.
          const limit = Math.min(Number(args.limit) || 8, 30)
          const ARENA_BASE = process.env.ARENA_BASE_URL || "https://arena.maxnexus.io"
          const [erroredConnsRes, failedActionsRes] = await Promise.all([
            supabase
              .from("arena_connections")
              .select("provider, label, last_error, last_used_at")
              .eq("user_id", USER_ID)
              .eq("status", "errored"),
            supabase
              .from("arena_action_log")
              .select("action, caller, error_msg, created_at")
              .eq("status", "error")
              .order("created_at", { ascending: false })
              .limit(limit),
          ])
          return JSON.stringify({
            success: true,
            errored_connections: erroredConnsRes.data ?? [],
            recent_failed_actions: failedActionsRes.data ?? [],
            manage_url: `${ARENA_BASE}/dashboard`,
            healthy: (erroredConnsRes.data?.length ?? 0) === 0 && (failedActionsRes.data?.length ?? 0) === 0,
          })
        }

        case "schedule_create": {
          // Validate + insert directly via service client (we already have
          // it). Mirror the validation done in /api/schedules POST so the
          // tool path can't bypass DB constraints.
          const { validateCron, nextRunAt } = await import("@/lib/schedules/parser")
          const VALID = new Set(["eve_chat", "agent_run", "operation_brief", "arena_action"])
          const name = (args.name as string | undefined)?.trim()
          const cron = (args.cron_expression as string | undefined)?.trim()
          const tz   = (args.timezone as string | undefined) || "America/Chicago"
          const targetType = args.target_type as string | undefined
          const targetId   = (args.target_id as string | undefined) || null
          const payload    = (args.payload as Record<string, unknown> | undefined) || {}
          const description = (args.description as string | undefined) || null

          if (!name)              return JSON.stringify({ success: false, error: "name required" })
          if (!targetType || !VALID.has(targetType)) {
            return JSON.stringify({ success: false, error: `target_type must be one of: ${[...VALID].join(", ")}` })
          }
          if (targetType !== "arena_action" && !targetId) {
            return JSON.stringify({ success: false, error: `${targetType} requires target_id` })
          }
          const valid = validateCron(cron ?? "", tz)
          if (!valid.ok) {
            return JSON.stringify({ success: false, error: `invalid cron: ${valid.reason}` })
          }
          let initial: string
          try { initial = nextRunAt(cron!, tz).toISOString() }
          catch (err) { return JSON.stringify({ success: false, error: err instanceof Error ? err.message : "could not compute next run" }) }

          const { data, error } = await supabase
            .from("schedules")
            .insert({
              user_id: USER_ID,
              name: name.slice(0, 200),
              description: description?.slice(0, 1000) ?? null,
              cron_expression: cron!,
              timezone: tz,
              target_type: targetType,
              target_id: targetId,
              payload,
              enabled: true,
              next_run_at: initial,
            })
            .select("id, name, cron_expression, timezone, next_run_at, target_type")
            .single()
          if (error) return JSON.stringify({ success: false, error: error.message })
          return JSON.stringify({ success: true, schedule: data, next_fires_at: data.next_run_at })
        }

        case "schedule_list": {
          const { data, error } = await supabase
            .from("schedules")
            .select("id, name, cron_expression, timezone, target_type, enabled, next_run_at, last_run_at, last_status")
            .eq("user_id", USER_ID)
            .order("created_at", { ascending: false })
          if (error) return JSON.stringify({ success: false, error: error.message })
          return JSON.stringify({
            success: true,
            count: data?.length ?? 0,
            schedules: data ?? [],
          })
        }

        // ── Terminal bridge tools ───────────────────────────────────────
        // Direct supabase access (same pattern as schedule_create/list).
        // The /api/terminal/* routes exist for Lumen + iOS clients; here
        // we go straight to the table because we already have USER_ID and
        // the service client. Stale-promotion mirrors the list route
        // (heartbeat > 2 min → "stale") so Eve sees what iOS sees.
        case "terminal_list": {
          const { data, error } = await supabase
            .from("terminal_sessions")
            .select("id, mac_label, folder, title, status, exit_code, last_snapshot_at, last_heartbeat_at, started_at, ended_at")
            .eq("user_id", USER_ID)
            .order("started_at", { ascending: false })
            .limit(50)
          if (error) return JSON.stringify({ success: false, error: error.message })
          const now = Date.now()
          const STALE_MS = 2 * 60 * 1000
          const promoted = (data ?? []).map(s => {
            if (s.status === "running" && s.last_heartbeat_at) {
              const hb = new Date(s.last_heartbeat_at).getTime()
              if (now - hb > STALE_MS) return { ...s, status: "stale" }
            }
            return s
          })
          const sessions = args.include_recent
            ? promoted
            : promoted.filter(s => s.status === "running" || s.status === "stale")
          return JSON.stringify({ success: true, count: sessions.length, sessions })
        }

        case "terminal_send":
        case "terminal_close": {
          // Resolve the target session. Prefer explicit id; fall back to a
          // fuzzy title/folder match. We only act on rows whose raw DB
          // status is 'running' — matching the /api/terminal/commands POST
          // check. A 'stale' session (heartbeat > 2 min) is still
          // 'running' in the DB, so Eve can poke at it; Lumen will pick
          // it up when it wakes.
          const sid = (args.session_id as string | undefined)?.trim()
          const match = (args.session_match as string | undefined)?.trim()
          if (!sid && !match) {
            return JSON.stringify({ success: false, error: "session_id or session_match is required" })
          }

          let session: { id: string; title: string | null; folder: string; status: string } | null = null
          if (sid) {
            const { data } = await supabase
              .from("terminal_sessions")
              .select("id, title, folder, status")
              .eq("user_id", USER_ID)
              .eq("id", sid)
              .maybeSingle()
            session = data
            if (!session) return JSON.stringify({ success: false, error: `No session with id ${sid}` })
          } else {
            const { data } = await supabase
              .from("terminal_sessions")
              .select("id, title, folder, status, last_heartbeat_at")
              .eq("user_id", USER_ID)
              .eq("status", "running")
              .or(`title.ilike.%${match}%,folder.ilike.%${match}%`)
              .order("last_heartbeat_at", { ascending: false })
            const candidates = data ?? []
            if (candidates.length === 0) {
              return JSON.stringify({ success: false, error: `No running session matches "${match}"` })
            }
            if (candidates.length > 1) {
              return JSON.stringify({
                success: false,
                error: `Multiple running sessions match "${match}". Ask the user which one.`,
                candidates: candidates.map(c => ({ id: c.id, title: c.title, folder: c.folder })),
              })
            }
            session = candidates[0]
          }

          if (session.status !== "running") {
            return JSON.stringify({ success: false, error: `Session is ${session.status}, not running.` })
          }

          // terminal_send appends \n so Eve doesn't have to remember.
          // terminal_close sends EOF (Ctrl-D, 0x04) — no newline.
          const command = name === "terminal_close"
            ? ""
            : `${(args.command as string ?? "").replace(/\n+$/, "")}\n`

          if (name === "terminal_send" && !command.trim()) {
            return JSON.stringify({ success: false, error: "command is empty" })
          }

          const { data, error } = await supabase
            .from("terminal_commands")
            .insert({
              session_id: session.id,
              user_id: USER_ID,
              command,
              status: "pending",
            })
            .select("id, submitted_at")
            .single()
          if (error || !data) {
            return JSON.stringify({ success: false, error: error?.message ?? "queue failed" })
          }
          return JSON.stringify({
            success: true,
            session: { id: session.id, title: session.title, folder: session.folder },
            command_id: data.id,
            queued_at: data.submitted_at,
            note: name === "terminal_close"
              ? "EOF queued — Lumen will deliver on its next 5s poll."
              : "Command queued — Lumen will deliver on its next 5s poll.",
          })
        }

        default:
          return JSON.stringify({ success: false, error: `Unknown tool: ${name}` })
      }
    } catch (e: any) {
      return JSON.stringify({ success: false, error: e.message })
    }
  }

  try {
    const client = new OpenAI({ apiKey: process.env.XAI_API_KEY!, baseURL: "https://api.x.ai/v1" })

    const apiMessages: OpenAI.Chat.ChatCompletionMessageParam[] = [...messages]

    // Agentic loop — up to 8 tool call rounds.
    // We collect every tool call and its result so the client can render
    // visible cards inline with Eve's natural-language reply ("Created task: …",
    // "Logged action: …", etc.) instead of having Eve's actions be invisible.
    type ToolCallTrace = {
      name: string
      args: Record<string, unknown>
      result: Record<string, unknown> | { success: boolean; error?: string }
    }
    const toolCallTrace: ToolCallTrace[] = []

    let assistantContent = ""
    for (let step = 0; step < 8; step++) {
      const response = await client.chat.completions.create({
        model: "grok-3-mini",
        messages: apiMessages,
        tools: toolDefs,
        tool_choice: "auto",
        max_tokens: 1024,
      })

      const choice = response.choices[0]
      apiMessages.push(choice.message)

      if (choice.message.tool_calls?.length) {
        const toolResults = await Promise.all(
          choice.message.tool_calls.map(async (tc) => {
            const args = JSON.parse(tc.function.arguments || "{}")
            const resultStr = await executeTool(tc.function.name, args)
            // Capture for client visualization
            let parsed: Record<string, unknown> = { success: false }
            try { parsed = JSON.parse(resultStr) } catch {}
            toolCallTrace.push({ name: tc.function.name, args, result: parsed })
            return { tool_call_id: tc.id, role: "tool" as const, content: resultStr }
          })
        )
        apiMessages.push(...toolResults)
        continue
      }

      // Final text response
      assistantContent = choice.message.content ?? ""
      break
    }

    // Persist assistant reply
    if (activeConversationId) {
      await supabase.from("eve_history").insert({ user_id: USER_ID, conversation_id: activeConversationId, role: "assistant", content: assistantContent, summarized: false })
    }

    // Auto-summarize every 20 unsummarized messages
    const { count } = await supabase.from("eve_history").select("*", { count: "exact", head: true }).eq("user_id", USER_ID).eq("summarized", false)
    if (count && count >= 20) {
      summarizeInBackground(supabase, USER_ID).catch(() => {})
    }

    // Streaming branch: when client requested SSE, run a SECOND completion in
    // streaming mode using the now-fully-resolved messages array (which has
    // any tool results baked in). The agentic loop above already produced
    // `assistantContent` non-streaming; we re-stream the same content so the
    // user sees Eve's reply appear progressively. Tool-call cards are emitted
    // as discrete events so the client can render them as the loop progresses.
    //
    // Trade-off: this is "perceived streaming" (we generate fully, then chunk
    // back) rather than true token-by-token streaming. Real streaming inside
    // the agentic loop is a future improvement.
    if (wantStream) {
      const encoder = new TextEncoder()
      const sse = new ReadableStream({
        async start(controller) {
          const write = (obj: Record<string, unknown>) => {
            controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`))
          }

          write({ type: "meta", conversationId: activeConversationId })

          // Tool call cards first so they appear as Eve "thinking through actions"
          for (const tc of toolCallTrace) {
            write({ type: "tool_call", name: tc.name, args: tc.args, result: tc.result })
            await new Promise(r => setTimeout(r, 80))  // tiny gap for visual cadence
          }

          // Stream the content in word-sized chunks for a typewriter feel
          const words = assistantContent.split(/(\s+)/)
          for (const w of words) {
            if (!w) continue
            write({ type: "delta", content: w })
            await new Promise(r => setTimeout(r, 18))  // ~55 wps reading pace
          }

          write({ type: "done", content: assistantContent, conversationId: activeConversationId })
          controller.close()
        }
      })

      return new Response(sse, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache, no-transform",
          "Connection": "keep-alive",
          "X-Accel-Buffering": "no",
        },
      })
    }

    return new Response(JSON.stringify({
      content: assistantContent,
      conversationId: activeConversationId,
      citations: [],
      tool_calls: toolCallTrace,
    }), {
      headers: { "Content-Type": "application/json" },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    })
  }
}
