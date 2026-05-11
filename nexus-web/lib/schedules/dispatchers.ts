// Schedule target dispatchers.
//
// Each function fires the side-effect for one target_type and returns a
// uniform result envelope. The runner takes that envelope and writes a
// schedule_runs row.
//
// All dispatchers run server-side under service-role auth, so they don't
// have a user session — they take user_id explicitly and operate on the
// owner's data scope.

import { createServiceClient } from "@/lib/supabase/service"

export type DispatchResult =
  | { status: "success"; result: Record<string, unknown> }
  | { status: "error"; error: string }

export type DispatchTarget = {
  scheduleId: string
  scheduleName: string
  userId: string
  targetType: "eve_chat" | "agent_run" | "operation_brief" | "arena_action"
  targetId: string | null
  payload: Record<string, unknown>
}

export async function dispatch(t: DispatchTarget): Promise<DispatchResult> {
  switch (t.targetType) {
    case "eve_chat":        return dispatchEveChat(t)
    case "agent_run":       return dispatchAgentRun(t)
    case "operation_brief": return dispatchOperationBrief(t)
    case "arena_action":    return dispatchArenaAction(t)
    default:                return { status: "error", error: `unknown target_type: ${t.targetType}` }
  }
}

// MARK: - eve_chat
//
// v1 semantics: write a user-role message into the target conversation
// (eve_history) prefixed with [scheduled: <name>] so it's visually distinct
// from a real Patrick turn. We do NOT auto-invoke Eve to respond — that
// requires a server-to-server eve invocation path that doesn't exist yet
// AND would race with any open browser tab. When Patrick (or whoever owns
// the schedule) next opens that conversation, they'll see the scheduled
// prompt sitting there as the latest user turn; sending any reply triggers
// Eve to respond to the whole thread including the scheduled message.
//
// Future v2: actually invoke Eve server-side and persist her response.
// Pairs naturally with Operation Notify (push the response when ready).

async function dispatchEveChat(t: DispatchTarget): Promise<DispatchResult> {
  const supabase = createServiceClient()
  const conversationId = t.targetId
  if (!conversationId) {
    return { status: "error", error: "eve_chat requires target_id (conversation_id)" }
  }
  const message = (t.payload.message as string | undefined)?.trim()
  if (!message) {
    return { status: "error", error: "eve_chat requires payload.message" }
  }

  // Verify the conversation belongs to the user — defense in depth even
  // though target_id was set when the schedule was created under that user.
  const { data: conv } = await supabase
    .from("eve_conversations")
    .select("id, user_id")
    .eq("id", conversationId)
    .maybeSingle()
  if (!conv || conv.user_id !== t.userId) {
    return { status: "error", error: "conversation not found or not owned by user" }
  }

  const display = `[scheduled: ${t.scheduleName}] ${message}`
  const { data: row, error } = await supabase
    .from("eve_history")
    .insert({
      user_id: t.userId,
      conversation_id: conversationId,
      role: "user",
      content: display,
      summarized: false,
    })
    .select("id")
    .single()

  if (error) return { status: "error", error: error.message }

  // Bump the conversation's updated_at so it sorts to the top of the sidebar.
  await supabase
    .from("eve_conversations")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", conversationId)

  return { status: "success", result: { messageId: row?.id, conversationId } }
}

// MARK: - agent_run

async function dispatchAgentRun(t: DispatchTarget): Promise<DispatchResult> {
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || "https://portal.maxnexus.io"
  const cronSecret = process.env.CRON_SECRET
  if (!cronSecret) return { status: "error", error: "CRON_SECRET not configured" }
  if (!t.targetId)  return { status: "error", error: "agent_run requires target_id (agent_id)" }

  try {
    const res = await fetch(`${baseUrl}/api/agents/run`, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${cronSecret}`,
        "x-internal-cron": "1",
        "x-cron-user-id": t.userId,
      },
      body: JSON.stringify({ agent_id: t.targetId, ...t.payload }),
    })
    const text = await res.text()
    if (!res.ok) return { status: "error", error: `agents/run ${res.status}: ${text.slice(0, 200)}` }
    let parsed: Record<string, unknown> = {}
    try { parsed = JSON.parse(text) as Record<string, unknown> } catch { /* keep empty */ }
    return { status: "success", result: parsed }
  } catch (err) {
    return { status: "error", error: err instanceof Error ? err.message : "agents/run network error" }
  }
}

// MARK: - operation_brief

async function dispatchOperationBrief(t: DispatchTarget): Promise<DispatchResult> {
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || "https://portal.maxnexus.io"
  const cronSecret = process.env.CRON_SECRET
  if (!cronSecret) return { status: "error", error: "CRON_SECRET not configured" }
  if (!t.targetId)  return { status: "error", error: "operation_brief requires target_id (operation_id)" }

  const kind = (t.payload.kind as string | undefined) || "summary"

  try {
    const res = await fetch(`${baseUrl}/api/operations/${t.targetId}/briefs`, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${cronSecret}`,
        "x-internal-cron": "1",
        "x-cron-user-id": t.userId,
      },
      body: JSON.stringify({ kind }),
    })
    const text = await res.text()
    if (!res.ok) return { status: "error", error: `operations/briefs ${res.status}: ${text.slice(0, 200)}` }
    let parsed: Record<string, unknown> = {}
    try { parsed = JSON.parse(text) as Record<string, unknown> } catch { /* keep empty */ }
    return { status: "success", result: { kind, ...parsed } }
  } catch (err) {
    return { status: "error", error: err instanceof Error ? err.message : "operations/briefs network error" }
  }
}

// MARK: - arena_action

async function dispatchArenaAction(t: DispatchTarget): Promise<DispatchResult> {
  const arenaBase = process.env.ARENA_BASE_URL || "https://arena.maxnexus.io"
  const arenaSecret = process.env.ARENA_SECRET
  if (!arenaSecret) return { status: "error", error: "ARENA_SECRET not configured" }

  const endpoint = (t.payload.endpoint as string | undefined)?.replace(/^\/+/, "")
  const body = (t.payload.body as Record<string, unknown> | undefined) || {}
  if (!endpoint) {
    return { status: "error", error: "arena_action requires payload.endpoint (e.g., 'api/task/create')" }
  }

  try {
    const res = await fetch(`${arenaBase}/${endpoint}`, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${arenaSecret}`,
        "X-Arena-Caller": `schedule:${t.scheduleId}`,
        "x-cron-user-id": t.userId,
      },
      body: JSON.stringify(body),
    })
    const text = await res.text()
    if (!res.ok) return { status: "error", error: `arena ${endpoint} ${res.status}: ${text.slice(0, 200)}` }
    let parsed: Record<string, unknown> = {}
    try { parsed = JSON.parse(text) as Record<string, unknown> } catch { /* keep empty */ }
    return { status: "success", result: parsed }
  } catch (err) {
    return { status: "error", error: err instanceof Error ? err.message : "arena network error" }
  }
}
