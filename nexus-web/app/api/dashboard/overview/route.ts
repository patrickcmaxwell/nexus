import { createServiceClient } from "@/lib/supabase/service"
import { USER_ID } from "@/lib/operations/auth"
import { NextResponse } from "next/server"

export const dynamic = "force-dynamic"

// One aggregated endpoint that powers the entire dashboard home page.
// Smart-polled from the client (10s when research is active, 30s otherwise).
// Keep this fast — parallel queries, small LIMITs, no heavyweight joins.

type ActivityItem = {
  id: string
  kind: "record_created" | "research_completed" | "research_started" | "brief_generated" | "conversation"
  title: string
  subtitle: string
  at: string
  href: string
  accent: string
}

export async function GET() {
  const supabase = createServiceClient()

  const [
    convRes,
    memRes,
    opRes,
    agentsRes,
    recCountRes,
    researchActiveRes,
    researchRecentRes,
    pinnedRecsRes,
    briefsActionsRes,
    recentRecordsRes,
    recentConvRes,
    arenaRes,
  ] = await Promise.all([
    // Counts
    supabase.from("eve_conversations").select("id", { count: "exact", head: true }).eq("user_id", USER_ID),
    supabase.from("eve_memory").select("id", { count: "exact", head: true }).eq("user_id", USER_ID).eq("is_active", true),
    supabase.from("operations").select("id, name, status, priority, codename, updated_at").eq("user_id", USER_ID).order("updated_at", { ascending: false }),
    supabase.from("agents").select("id, name, role, status, last_scanned_at, total_findings").eq("user_id", USER_ID).order("created_at", { ascending: false }),
    supabase.from("operation_records").select("id", { count: "exact", head: true }).eq("user_id", USER_ID).is("archived_at", null),

    // Active research (queued + running)
    supabase
      .from("research_jobs")
      .select("id, operation_id, record_id, model, status, prompt, progress_note, findings_count, started_at, created_at")
      .eq("user_id", USER_ID)
      .in("status", ["queued", "running"])
      .order("created_at", { ascending: false })
      .limit(8),

    // Recently completed/failed research for activity feed
    supabase
      .from("research_jobs")
      .select("id, operation_id, record_id, model, status, prompt, result_summary, findings_count, completed_at")
      .eq("user_id", USER_ID)
      .in("status", ["complete", "completed", "failed"])
      .order("completed_at", { ascending: false })
      .limit(8),

    // Pinned + high-priority records
    supabase
      .from("operation_records")
      .select("id, operation_id, title, type, status, priority, pinned, updated_at")
      .eq("user_id", USER_ID)
      .is("archived_at", null)
      .or("pinned.eq.true,priority.in.(high,critical)")
      .order("pinned", { ascending: false })
      .order("updated_at", { ascending: false })
      .limit(12),

    // Action items — latest 'actions' and 'next_steps' briefs
    supabase
      .from("operation_briefs")
      .select("id, operation_id, kind, content, generated_at")
      .eq("user_id", USER_ID)
      .in("kind", ["actions", "next_steps"])
      .order("generated_at", { ascending: false })
      .limit(6),

    // Recent record activity (for feed)
    supabase
      .from("operation_records")
      .select("id, operation_id, title, type, created_at")
      .eq("user_id", USER_ID)
      .is("archived_at", null)
      .order("created_at", { ascending: false })
      .limit(8),

    // Most recent conversation + its last messages
    supabase
      .from("eve_conversations")
      .select("id, title, updated_at, created_at")
      .eq("user_id", USER_ID)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),

    // Recent Arena executor activity (Eve's real-world side effects)
    supabase
      .from("arena_action_log")
      .select("id, action, caller, payload, result, status, created_at")
      .order("created_at", { ascending: false })
      .limit(8),
  ])

  const operations = opRes.data ?? []
  const opById = new Map(operations.map(o => [o.id, o]))
  const opName = (id: string | null | undefined) => (id ? opById.get(id)?.name ?? "Operation" : "Operation")

  // Load last messages for the most-recent conversation (for the "resume" panel)
  let lastConversation: { id: string; title: string; messages: Array<{ role: string; content: string; created_at: string }> } | null = null
  if (recentConvRes.data) {
    const { data: msgs } = await supabase
      .from("eve_history")
      .select("id, role, content, created_at")
      .eq("conversation_id", recentConvRes.data.id)
      .order("created_at", { ascending: false })
      .limit(4)
    lastConversation = {
      id: recentConvRes.data.id,
      title: recentConvRes.data.title ?? "Untitled",
      messages: (msgs ?? []).reverse(),
    }
  }

  // Enrich pinned records with operation name
  const pinnedRecords = (pinnedRecsRes.data ?? []).map(r => ({
    ...r,
    operation_name: opName(r.operation_id),
  }))

  // Enrich active research jobs with operation name + record title lookup (single batched query)
  const activeResearch = researchActiveRes.data ?? []
  const recIds = Array.from(new Set(activeResearch.map(j => j.record_id).filter((x): x is string => !!x)))
  let recTitleMap = new Map<string, string>()
  if (recIds.length) {
    const { data: recs } = await supabase
      .from("operation_records")
      .select("id, title")
      .in("id", recIds)
    recTitleMap = new Map((recs ?? []).map(r => [r.id, r.title]))
  }
  const activeResearchEnriched = activeResearch.map(j => ({
    ...j,
    operation_name: opName(j.operation_id),
    record_title: j.record_id ? recTitleMap.get(j.record_id) ?? null : null,
  }))

  // Parse action items out of brief content. Briefs are markdown-ish;
  // we extract the first ~4 bullet lines from each brief.
  const actionItems = (briefsActionsRes.data ?? []).flatMap(b => {
    const lines = (b.content ?? "")
      .split("\n")
      .map((l: string) => l.trim())
      .filter((l: string) => /^[-*•]\s+|^\d+\.\s+/.test(l))
      .slice(0, 4)
      .map((l: string) => l.replace(/^[-*•]\s+|^\d+\.\s+/, ""))
    return lines.map((text: string, i: number) => ({
      id: `${b.id}-${i}`,
      brief_id: b.id,
      operation_id: b.operation_id,
      operation_name: opName(b.operation_id),
      kind: b.kind as "actions" | "next_steps",
      text,
      generated_at: b.generated_at,
    }))
  }).slice(0, 8)

  // Build unified activity feed
  const activity: ActivityItem[] = []

  for (const r of recentRecordsRes.data ?? []) {
    activity.push({
      id: `rec-${r.id}`,
      kind: "record_created",
      title: r.title,
      subtitle: `${r.type} in ${opName(r.operation_id)}`,
      at: r.created_at,
      href: `/dashboard/operations?record=${r.id}`,
      accent: "#fbbf24",
    })
  }
  for (const j of researchRecentRes.data ?? []) {
    if (!j.completed_at) continue
    const isFail = j.status === "failed"
    activity.push({
      id: `jobdone-${j.id}`,
      kind: isFail ? "research_started" : "research_completed",
      title: isFail ? "Research failed" : `Research complete — ${j.findings_count ?? 0} findings`,
      subtitle: j.prompt?.slice(0, 70) ?? opName(j.operation_id),
      at: j.completed_at,
      href: j.record_id
        ? `/dashboard/operations?record=${j.record_id}`
        : "/dashboard/operations",
      accent: isFail ? "#ef4444" : "#06b6d4",
    })
  }
  for (const j of researchActiveRes.data ?? []) {
    if (j.status !== "running") continue
    activity.push({
      id: `jobstart-${j.id}`,
      kind: "research_started",
      title: "Research in progress",
      subtitle: j.progress_note ?? j.prompt?.slice(0, 70) ?? opName(j.operation_id),
      at: j.started_at ?? j.created_at,
      href: j.record_id ? `/dashboard/operations?record=${j.record_id}` : "/dashboard/operations",
      accent: "#06b6d4",
    })
  }
  // Pull last handful of eve_conversations as activity too
  const { data: recentConvs } = await supabase
    .from("eve_conversations")
    .select("id, title, updated_at")
    .eq("user_id", USER_ID)
    .order("updated_at", { ascending: false })
    .limit(4)
  for (const c of recentConvs ?? []) {
    activity.push({
      id: `conv-${c.id}`,
      kind: "conversation",
      title: c.title ?? "Conversation",
      subtitle: "Eve session",
      at: c.updated_at,
      href: `/dashboard/maxwell?c=${c.id}`,
      accent: "#00d4ff",
    })
  }

  activity.sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime())

  // Compose a contextual greeting. Kept terse — Eve style.
  const hour = new Date().getHours()
  const period = hour < 5 ? "evening" : hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
  const activeCount = activeResearch.length
  const pinnedCount = pinnedRecords.filter(r => r.pinned).length
  const highCount = pinnedRecords.filter(r => !r.pinned).length
  const activeOps = operations.filter(o => o.status === "active").length

  const parts: string[] = [`Good ${period}, sir.`]
  if (activeCount > 0) {
    parts.push(`${activeCount} research ${activeCount === 1 ? "job" : "jobs"} in progress.`)
  }
  if (pinnedCount > 0) {
    parts.push(`${pinnedCount} pinned ${pinnedCount === 1 ? "record" : "records"} awaiting review.`)
  }
  if (activeOps > 0 && activeCount === 0 && pinnedCount === 0) {
    parts.push(`${activeOps} active ${activeOps === 1 ? "operation" : "operations"} on deck.`)
  }
  if (activeCount === 0 && pinnedCount === 0 && highCount === 0 && activeOps === 0) {
    parts.push("All systems nominal. What's the objective?")
  } else {
    parts.push("Where should we start?")
  }
  const greeting = parts.join(" ")

  // Generate 3 contextual follow-up suggestions for the Ask-Eve chips
  const suggestions: string[] = []
  if (activeCount > 0) {
    const j = activeResearchEnriched[0]
    suggestions.push(`Status on ${j.operation_name} research`)
  }
  if (pinnedCount > 0) {
    suggestions.push("What should I review first?")
  }
  if (actionItems.length > 0) {
    suggestions.push(`Walk me through ${actionItems[0].operation_name}`)
  }
  if (lastConversation) {
    suggestions.push(`Pick up where we left off`)
  }
  if (suggestions.length < 3) {
    suggestions.push("Summarize everything active")
    suggestions.push("Start a new research job")
    suggestions.push("Draft a status report")
  }
  const suggestionsOut = Array.from(new Set(suggestions)).slice(0, 3)

  return NextResponse.json({
    greeting,
    suggestions: suggestionsOut,
    stats: {
      conversations: convRes.count ?? 0,
      memories: memRes.count ?? 0,
      operations: operations.length,
      agents: (agentsRes.data ?? []).length,
      records: recCountRes.count ?? 0,
      activeOperations: activeOps,
      activeResearch: activeCount,
    },
    operations: operations.slice(0, 6),
    agents: agentsRes.data ?? [],
    activeResearch: activeResearchEnriched,
    pinnedRecords,
    actionItems,
    activity: activity.slice(0, 20),
    lastConversation,
    arena: arenaRes.data ?? [],
  })
}
