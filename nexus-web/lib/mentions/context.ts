import type { SupabaseClient } from "@supabase/supabase-js"
import type { MentionToken } from "./types"

// Fetch full context for every mention in a message and format it as a
// compact block that can be prepended to Eve's system prompt. This is what
// makes "Eve already knows what @arcology-project is" feel like magic —
// she gets the name, status, objectives, active directives, recent records,
// and active research for that operation without the user typing any of it.
//
// All queries run in parallel per mention, and across mentions.

type Any = Record<string, unknown>
function asString(v: unknown): string { return typeof v === "string" ? v : "" }
function asArray(v: unknown): unknown[] { return Array.isArray(v) ? v : [] }

async function fetchOperationContext(supabase: SupabaseClient, userId: string, id: string): Promise<string | null> {
  // Operation metadata
  const { data: op } = await supabase
    .from("operations")
    .select("id, name, codename, description, status, priority, objectives, directives, tags")
    .eq("user_id", userId).eq("id", id).maybeSingle()
  if (!op) return null

  // Run the three follow-up queries in parallel
  const [recordsRes, researchRes, briefsRes] = await Promise.all([
    supabase.from("operation_records")
      .select("title, type, created_at, pinned, priority")
      .eq("operation_id", id).eq("user_id", userId).eq("archived", false)
      .order("created_at", { ascending: false }).limit(8),
    supabase.from("research_jobs")
      .select("topic, status, progress_note, model")
      .eq("operation_id", id).eq("user_id", userId)
      .in("status", ["queued", "running"]).limit(5),
    supabase.from("operation_briefs")
      .select("kind, content, created_at")
      .eq("operation_id", id).eq("user_id", userId)
      .order("created_at", { ascending: false }).limit(2),
  ])

  const lines: string[] = []
  const opAny = op as Any
  lines.push(`Operation "${asString(opAny.name)}"${opAny.codename ? ` (codename: ${asString(opAny.codename)})` : ""} [id:${asString(opAny.id)}]`)
  if (opAny.status) lines.push(`  Status: ${asString(opAny.status)}${opAny.priority ? ` · priority ${asString(opAny.priority)}` : ""}`)
  if (opAny.description) lines.push(`  Description: ${asString(opAny.description)}`)

  // objectives can be jsonb array or string — normalize
  if (opAny.objectives) {
    const objs = Array.isArray(opAny.objectives)
      ? opAny.objectives.map(asString).filter(Boolean)
      : asString(opAny.objectives) ? [asString(opAny.objectives)] : []
    if (objs.length) lines.push(`  Objectives: ${objs.join("; ")}`)
  }
  if (opAny.directives) lines.push(`  Standing directives: ${asString(opAny.directives)}`)
  if (opAny.tags) {
    const tags = asArray(opAny.tags).map(asString).filter(Boolean)
    if (tags.length) lines.push(`  Tags: ${tags.join(", ")}`)
  }

  const records = recordsRes.data ?? []
  if (records.length) {
    lines.push(`  Recent records (${records.length}):`)
    for (const r of records) {
      const ra = r as Any
      const flags: string[] = []
      if (ra.pinned) flags.push("pinned")
      if (ra.priority === "high" || ra.priority === "critical") flags.push(asString(ra.priority))
      const flagStr = flags.length ? ` [${flags.join(", ")}]` : ""
      lines.push(`    - ${asString(ra.type)}: ${asString(ra.title)}${flagStr}`)
    }
  }
  const research = researchRes.data ?? []
  if (research.length) {
    lines.push(`  Active research:`)
    for (const j of research) {
      const ja = j as Any
      lines.push(`    - [${asString(ja.status)}] ${asString(ja.topic)}${ja.progress_note ? ` — ${asString(ja.progress_note)}` : ""}`)
    }
  }
  const briefs = briefsRes.data ?? []
  if (briefs.length) {
    lines.push(`  Latest briefs:`)
    for (const b of briefs) {
      const ba = b as Any
      const snippet = asString(ba.content).slice(0, 200).replace(/\s+/g, " ")
      lines.push(`    - [${asString(ba.kind)}] ${snippet}${asString(ba.content).length > 200 ? "…" : ""}`)
    }
  }
  return lines.join("\n")
}

async function fetchRecordContext(supabase: SupabaseClient, userId: string, id: string): Promise<string | null> {
  const { data } = await supabase
    .from("operation_records")
    .select("id, title, type, content, pinned, priority, created_at, operations!inner(name, codename)")
    .eq("user_id", userId).eq("id", id).maybeSingle()
  if (!data) return null
  const d = data as Any
  const op = d.operations as Any
  const opName = op ? `${asString(op.name)}${op.codename ? ` (${asString(op.codename)})` : ""}` : "unknown op"

  const lines: string[] = []
  lines.push(`Record "${asString(d.title)}" [${asString(d.type)}, id:${asString(d.id)}]`)
  lines.push(`  Part of operation: ${opName}`)
  if (d.pinned) lines.push(`  Pinned`)
  if (d.priority === "high" || d.priority === "critical") lines.push(`  Priority: ${asString(d.priority)}`)
  const content = asString(d.content)
  // Cap body at ~2000 chars so a huge record doesn't blow the token budget.
  const truncated = content.length > 2000 ? content.slice(0, 2000) + "…" : content
  if (truncated) lines.push(`  Content:\n${truncated}`)
  return lines.join("\n")
}

async function fetchConversationContext(supabase: SupabaseClient, userId: string, id: string): Promise<string | null> {
  const { data: conv } = await supabase
    .from("eve_conversations")
    .select("id, title, summary, created_at, updated_at")
    .eq("user_id", userId).eq("id", id).maybeSingle()
  if (!conv) return null

  // If there's no stored summary, synthesize one from the last handful of
  // messages. Cheaper than re-summarizing server-side each time.
  const { data: tail } = await supabase
    .from("eve_history")
    .select("role, content, created_at")
    .eq("conversation_id", id).eq("user_id", userId)
    .order("created_at", { ascending: false }).limit(6)

  const c = conv as Any
  const lines: string[] = []
  lines.push(`Conversation "${asString(c.title)}" [id:${asString(c.id)}]`)
  if (c.summary) lines.push(`  Summary: ${asString(c.summary)}`)
  if (tail && tail.length) {
    lines.push(`  Recent exchange (${tail.length} messages):`)
    // Reverse so it reads chronologically
    for (const m of [...tail].reverse()) {
      const ma = m as Any
      const speaker = ma.role === "user" ? "Director" : "Eve"
      const snippet = asString(ma.content).slice(0, 240).replace(/\s+/g, " ")
      lines.push(`    ${speaker}: ${snippet}${asString(ma.content).length > 240 ? "…" : ""}`)
    }
  }
  return lines.join("\n")
}

async function fetchTopicContext(supabase: SupabaseClient, userId: string, id: string): Promise<string | null> {
  const { data } = await supabase
    .from("eve_topics")
    .select("label, description, color, eve_conversations!inner(title)")
    .eq("user_id", userId).eq("id", id).maybeSingle()
  if (!data) return null
  const d = data as Any
  const conv = d.eve_conversations as Any
  const lines: string[] = [`Topic "${asString(d.label)}" [id:${id}]`]
  if (d.description) lines.push(`  Description: ${asString(d.description)}`)
  if (conv?.title) lines.push(`  From conversation: ${asString(conv.title)}`)
  return lines.join("\n")
}

async function fetchAgentContext(supabase: SupabaseClient, userId: string, id: string): Promise<string | null> {
  const { data } = await supabase
    .from("agents")
    .select("name, role, status, personality, capabilities, directives")
    .eq("user_id", userId).eq("id", id).maybeSingle()
  if (!data) return null
  const d = data as Any
  const lines: string[] = [`Agent "${asString(d.name)}" [${asString(d.status)}, id:${id}]`]
  if (d.role) lines.push(`  Role: ${asString(d.role)}`)
  if (d.personality) lines.push(`  Personality: ${asString(d.personality)}`)
  const caps = asArray(d.capabilities).map(asString).filter(Boolean)
  if (caps.length) lines.push(`  Capabilities: ${caps.join(", ")}`)
  if (d.directives) lines.push(`  Directives: ${asString(d.directives)}`)
  return lines.join("\n")
}

// Public entry: take a list of mention tokens, fetch them all in parallel,
// and return a single <mentions>...</mentions> block ready to splice into
// a system prompt. Returns null if nothing resolves.
export async function buildMentionsBlock(
  supabase: SupabaseClient,
  userId: string,
  tokens: MentionToken[],
): Promise<string | null> {
  if (!tokens.length) return null

  const results = await Promise.all(tokens.map(async (t) => {
    try {
      switch (t.type) {
        case "operation":    return await fetchOperationContext(supabase, userId, t.id)
        case "record":       return await fetchRecordContext(supabase, userId, t.id)
        case "conversation": return await fetchConversationContext(supabase, userId, t.id)
        case "topic":        return await fetchTopicContext(supabase, userId, t.id)
        case "agent":        return await fetchAgentContext(supabase, userId, t.id)
        default:             return null
      }
    } catch {
      // Never let a context lookup failure break the chat turn.
      return null
    }
  }))

  const blocks = results.filter((x): x is string => !!x)
  if (!blocks.length) return null

  return [
    "<mentions>",
    "The Director referenced the following entities in this message. Treat each block as authoritative context you already know — you do not need to ask for clarification or call any tools to retrieve this info.",
    "",
    ...blocks.map(b => b + "\n"),
    "</mentions>",
  ].join("\n")
}
