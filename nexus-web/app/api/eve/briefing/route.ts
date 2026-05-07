// /api/eve/briefing
//
// Returns a "what changed since last visit" delta any client can render at
// the top of an empty-state Eve dashboard. Powers Lumen's EveBriefingView,
// nexus-web's Eve home, and (eventually) iOS.
//
// Query: ?since=<ISO timestamp> (optional). If omitted, defaults to 24h ago.
// Auth: same as the rest of /api/eve/* — Bearer for desktop, cookie for web.

import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { checkDesktopAuth } from "@/lib/desktop-auth"
import { NextRequest, NextResponse } from "next/server"

export const dynamic = "force-dynamic"

export async function GET(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId || !await checkDesktopAuth(req)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { searchParams } = new URL(req.url)
  const sinceParam = searchParams.get("since")
  const since = sinceParam
    ? new Date(sinceParam).toISOString()
    : new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
  const now = new Date().toISOString()

  const supabase = createServiceClient()

  const [
    newOpsRes,
    statusChangedOpsRes,
    newRecordsRes,
    findingsRes,
    completedResearchRes,
    activeOpsRes,
    activeAgentsRes,
    directivesRes,
    memoriesRes,
  ] = await Promise.all([
    // Operations created since the cutoff
    supabase
      .from("operations")
      .select("id, name, codename, status, priority, created_at")
      .eq("user_id", userId)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(20),
    // Operations whose updated_at moved past the cutoff but were created before
    supabase
      .from("operations")
      .select("id, name, codename, status, priority, updated_at, created_at")
      .eq("user_id", userId)
      .gte("updated_at", since)
      .lt("created_at", since)
      .order("updated_at", { ascending: false })
      .limit(20),
    // New records
    supabase
      .from("operation_records")
      .select("id, title, type, priority, operation_id, created_at")
      .eq("user_id", userId)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(20),
    // Recent agent findings
    supabase
      .from("agent_activity")
      .select("id, agent_id, action, summary, created_at")
      .eq("user_id", userId)
      .gte("created_at", since)
      .ilike("action", "%finding%")
      .order("created_at", { ascending: false })
      .limit(30),
    // Completed research
    supabase
      .from("research_jobs")
      .select("id, operation_id, model, status, result_summary, completed_at")
      .eq("user_id", userId)
      .gte("completed_at", since)
      .in("status", ["complete", "completed"])
      .order("completed_at", { ascending: false })
      .limit(10),
    // Stats: active ops/agents, totals
    supabase.from("operations")
      .select("id, name, codename, status, priority", { count: "exact" })
      .eq("user_id", userId)
      .eq("status", "active"),
    supabase.from("agents")
      .select("id, name, role, status, total_findings, last_scanned_at", { count: "exact" })
      .eq("user_id", userId)
      .eq("status", "active"),
    supabase.from("eve_directives")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("is_active", true),
    supabase.from("eve_memory")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("is_active", true),
  ])

  // Build per-agent finding rollup
  const findingsByAgent: Record<string, number> = {}
  for (const row of findingsRes.data ?? []) {
    findingsByAgent[row.agent_id] = (findingsByAgent[row.agent_id] ?? 0) + 1
  }

  // Resolve agent IDs to names so the client doesn't need a second lookup.
  const agentIds = Object.keys(findingsByAgent)
  let agentNameById: Record<string, string> = {}
  if (agentIds.length > 0) {
    const { data: agentRows } = await supabase
      .from("agents")
      .select("id, name")
      .eq("user_id", userId)
      .in("id", agentIds)
    for (const a of agentRows ?? []) {
      agentNameById[a.id] = a.name as string
    }
  }

  // Resolve op IDs in records → friendly op codename/name
  const opIds = Array.from(new Set((newRecordsRes.data ?? []).map(r => r.operation_id).filter(Boolean) as string[]))
  let opLabelById: Record<string, string> = {}
  if (opIds.length > 0) {
    const { data: opRows } = await supabase
      .from("operations")
      .select("id, name, codename")
      .eq("user_id", userId)
      .in("id", opIds)
    for (const o of opRows ?? []) {
      opLabelById[o.id] = (o.codename as string) || (o.name as string)
    }
  }

  return NextResponse.json({
    since,
    now,
    stats: {
      activeOps: activeOpsRes.count ?? 0,
      activeAgents: activeAgentsRes.count ?? 0,
      activeDirectives: directivesRes.count ?? 0,
      memories: memoriesRes.count ?? 0,
    },
    delta: {
      newOperations: (newOpsRes.data ?? []).map(o => ({
        id: o.id,
        label: (o.codename as string) || (o.name as string),
        name: o.name,
        status: o.status,
        priority: o.priority,
        createdAt: o.created_at,
      })),
      statusChangedOperations: (statusChangedOpsRes.data ?? []).map(o => ({
        id: o.id,
        label: (o.codename as string) || (o.name as string),
        status: o.status,
        priority: o.priority,
        updatedAt: o.updated_at,
      })),
      newRecords: (newRecordsRes.data ?? []).map(r => ({
        id: r.id,
        title: r.title,
        type: r.type,
        priority: r.priority,
        operationLabel: opLabelById[r.operation_id ?? ""] ?? "",
        operationId: r.operation_id,
        createdAt: r.created_at,
      })),
      findings: {
        totalCount: (findingsRes.data ?? []).length,
        perAgent: Object.fromEntries(
          Object.entries(findingsByAgent).map(([id, count]) => [
            agentNameById[id] ?? id, count,
          ])
        ),
        latest: (findingsRes.data ?? []).slice(0, 8).map(f => ({
          agent: agentNameById[f.agent_id] ?? f.agent_id,
          summary: f.summary,
          createdAt: f.created_at,
        })),
      },
      completedResearch: (completedResearchRes.data ?? []).map(r => ({
        id: r.id,
        operationId: r.operation_id,
        operationLabel: opLabelById[r.operation_id ?? ""] ?? "",
        model: r.model,
        summary: (r.result_summary as string)?.slice(0, 200) ?? "",
        completedAt: r.completed_at,
      })),
    },
  })
}
