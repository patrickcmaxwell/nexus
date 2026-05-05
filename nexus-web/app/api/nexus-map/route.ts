import { createServiceClient } from "@/lib/supabase/service"
import { NextRequest, NextResponse } from "next/server"
import { checkDesktopAuth } from "@/lib/desktop-auth"

import { getActiveAuthId } from "@/lib/auth/session"

export type MapNodeType =
  | "conversation"
  | "agent"
  | "operation"
  | "topic"
  | "record"
  | "research"
  | "directive"
  | "human"

export interface MapNode {
  id: string
  type: MapNodeType
  title: string
  subtitle: string
  preview: string
  tags: string[]
  status?: string | null
  priority?: string | null
  pinned?: boolean
  archived?: boolean
  messageCount: number
  createdAt: string
  updatedAt: string
  // Hierarchy / provenance
  parentId?: string | null          // operation for records, record for research/children
  sourceConversationId?: string | null
  // Research-specific
  progressNote?: string | null
  findingsCount?: number | null
  model?: string | null
}

export interface MapEdge {
  source: string
  target: string
  type: "topic-link" | "temporal" | "record-belongs-to" | "record-source" | "record-parent" | "research-on" | "research-producing"
}

export async function GET(req: NextRequest) {
  const USER_ID = await getActiveAuthId()
  if (!USER_ID) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  if (!await checkDesktopAuth(req)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const supabase = createServiceClient()

  // Fetch every surface of the system in parallel
  const [
    convRes,
    agentsRes,
    operationsRes,
    mapNodesRes,
    recordsRes,
    researchRes,
    directivesRes,
    humansRes,
  ] = await Promise.all([
    supabase
      .from("eve_conversations")
      .select("id, title, created_at, updated_at, source")
      .eq("user_id", USER_ID)
      .order("updated_at", { ascending: false }),
    supabase
      .from("agents")
      .select("id, name, role, status, personality, capabilities, created_at, updated_at")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }),
    supabase
      .from("operations")
      .select("id, name, description, status, priority, created_at, updated_at, tags")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }),
    supabase
      .from("nexus_map_nodes")
      .select("id, label, description, tags, source_conversation_id, created_at, updated_at")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }),
    supabase
      .from("operation_records")
      .select("id, operation_id, type, title, content, status, priority, source, pinned, archived_at, parent_record_id, source_conversation_id, created_at, updated_at")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }),
    supabase
      .from("research_jobs")
      .select("id, operation_id, record_id, status, progress_note, started_at, completed_at, model, assigned_to, findings_count, error, result_record_ids, created_at")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }),
    supabase
      .from("eve_directives")
      .select("id, title, content, type, priority, is_active, target, created_at, updated_at")
      .eq("user_id", USER_ID)
      .order("priority", { ascending: false }),
    supabase
      .from("team_members")
      .select("id, name, role, status, created_at")
      .order("created_at", { ascending: true }),
  ])

  const conversations = convRes.data
  const agents = agentsRes.data
  const operations = operationsRes.data
  const mapNodes = mapNodesRes.data
  const records = recordsRes.data
  const research = researchRes.data
  const directives = directivesRes.data
  const humans = humansRes.data

  const nodes: MapNode[] = []

  // --- Conversations ---
  if (conversations) {
    const convWithCounts = await Promise.all(
      conversations.map(async (conv) => {
        const { count } = await supabase
          .from("eve_history")
          .select("*", { count: "exact", head: true })
          .eq("user_id", USER_ID)
          .eq("conversation_id", conv.id)

        const { data: lastMsg } = await supabase
          .from("eve_history")
          .select("content")
          .eq("user_id", USER_ID)
          .eq("conversation_id", conv.id)
          .eq("role", "assistant")
          .order("created_at", { ascending: false })
          .limit(1)
          .single()

        return {
          id: conv.id,
          type: "conversation" as const,
          title: conv.title ?? "Untitled",
          subtitle: "Eve Session",
          preview: lastMsg?.content?.slice(0, 100) ?? "",
          tags: [],
          messageCount: count ?? 0,
          createdAt: conv.created_at,
          updatedAt: conv.updated_at,
        } satisfies MapNode
      })
    )
    nodes.push(...convWithCounts)
  }

  // --- Agents ---
  if (agents) {
    for (const agent of agents) {
      nodes.push({
        id: `agent-${agent.id}`,
        type: "agent",
        title: agent.name,
        subtitle: agent.role ?? "",
        preview: agent.personality ?? "",
        tags: agent.capabilities ?? [],
        status: agent.status,
        messageCount: 0,
        createdAt: agent.created_at,
        updatedAt: agent.updated_at ?? agent.created_at,
      })
    }
  }

  // --- Operations ---
  if (operations) {
    for (const op of operations) {
      nodes.push({
        id: `op-${op.id}`,
        type: "operation",
        title: op.name,
        subtitle: `${op.priority ?? "medium"} priority`,
        preview: op.description ?? "",
        tags: [...(op.tags ?? []), op.status ?? "planning"].filter(Boolean),
        status: op.status,
        priority: op.priority,
        messageCount: 0,
        createdAt: op.created_at,
        updatedAt: op.updated_at ?? op.created_at,
      })
    }
  }

  // --- Custom topic nodes ---
  if (mapNodes) {
    for (const n of mapNodes) {
      nodes.push({
        id: `topic-${n.id}`,
        type: "topic",
        title: n.label,
        subtitle: "Topic Node",
        preview: n.description ?? "",
        tags: n.tags ?? [],
        messageCount: 0,
        createdAt: n.created_at,
        updatedAt: n.updated_at ?? n.created_at,
        sourceConversationId: n.source_conversation_id,
      })
    }
  }

  // --- Operation records ---
  if (records) {
    for (const r of records) {
      nodes.push({
        id: `rec-${r.id}`,
        type: "record",
        title: r.title ?? "Untitled record",
        subtitle: `${r.type ?? "note"}${r.source ? ` · via ${r.source}` : ""}`,
        preview: r.content ?? "",
        tags: [r.type, r.status].filter(Boolean) as string[],
        status: r.status,
        priority: r.priority,
        pinned: !!r.pinned,
        archived: !!r.archived_at,
        messageCount: 0,
        createdAt: r.created_at,
        updatedAt: r.updated_at ?? r.created_at,
        parentId: r.parent_record_id ? `rec-${r.parent_record_id}` : (r.operation_id ? `op-${r.operation_id}` : null),
        sourceConversationId: r.source_conversation_id,
      })
    }
  }

  // --- Research jobs ---
  if (research) {
    for (const j of research) {
      const isDone = j.status === "complete" || j.status === "completed"
      nodes.push({
        id: `research-${j.id}`,
        type: "research",
        title: j.progress_note || (isDone ? "Research complete" : "Research job"),
        subtitle: `${j.model ?? j.assigned_to ?? "eve"} · ${j.status}`,
        preview: j.error ? `Error: ${j.error}` : (j.progress_note ?? ""),
        tags: [j.status, j.assigned_to ?? j.model].filter(Boolean) as string[],
        status: j.status,
        messageCount: 0,
        createdAt: j.created_at,
        updatedAt: j.completed_at ?? j.started_at ?? j.created_at,
        parentId: j.record_id ? `rec-${j.record_id}` : (j.operation_id ? `op-${j.operation_id}` : null),
        progressNote: j.progress_note,
        findingsCount: j.findings_count ?? 0,
        model: j.model ?? j.assigned_to,
      })
    }
  }

  // --- Directives & protocols ---
  if (directives) {
    for (const d of directives) {
      nodes.push({
        id: `directive-${d.id}`,
        type: "directive",
        title: d.title,
        subtitle: `${d.type ?? "directive"}${d.target ? ` · ${d.target}` : ""}`,
        preview: d.content ?? "",
        tags: [d.type, d.is_active ? "active" : "inactive"].filter(Boolean) as string[],
        status: d.is_active ? "active" : "inactive",
        priority: String(d.priority ?? ""),
        messageCount: 0,
        createdAt: d.created_at,
        updatedAt: d.updated_at ?? d.created_at,
      })
    }
  }

  // --- Humans ---
  if (humans) {
    for (const h of humans) {
      nodes.push({
        id: `human-${h.id}`,
        type: "human",
        title: h.name,
        subtitle: `Role: ${h.role}`,
        preview: "Human Operator connected to Nexus",
        tags: [h.status].filter(Boolean) as string[],
        status: h.status,
        messageCount: 0,
        createdAt: h.created_at,
        updatedAt: h.created_at,
      })
    }
  }

  // ─── Edges ───────────────────────────────────────────────────────────────────
  const edges: MapEdge[] = []

  // Topic nodes → their source conversation
  for (const node of nodes) {
    if (node.type === "topic" && node.sourceConversationId) {
      edges.push({ source: node.sourceConversationId, target: node.id, type: "topic-link" })
    }
  }

  // Record → operation OR parent record
  if (records) {
    for (const r of records) {
      if (r.parent_record_id) {
        edges.push({ source: `rec-${r.parent_record_id}`, target: `rec-${r.id}`, type: "record-parent" })
      } else if (r.operation_id) {
        edges.push({ source: `op-${r.operation_id}`, target: `rec-${r.id}`, type: "record-belongs-to" })
      }
      if (r.source_conversation_id) {
        edges.push({ source: r.source_conversation_id, target: `rec-${r.id}`, type: "record-source" })
      }
    }
  }

  // Research → target record (what it's researching) + child records it produced
  if (research) {
    for (const j of research) {
      if (j.record_id) {
        edges.push({ source: `rec-${j.record_id}`, target: `research-${j.id}`, type: "research-on" })
      }
      if (j.result_record_ids && Array.isArray(j.result_record_ids)) {
        for (const rid of j.result_record_ids) {
          edges.push({ source: `research-${j.id}`, target: `rec-${rid}`, type: "research-producing" })
        }
      }
    }
  }

  // Temporal: sequential close-in-time conversations
  const convNodes = nodes.filter(n => n.type === "conversation")
    .sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime())
  for (let i = 0; i < convNodes.length - 1; i++) {
    const diffMin = (new Date(convNodes[i + 1].createdAt).getTime() - new Date(convNodes[i].updatedAt).getTime()) / 60000
    if (diffMin < 60) {
      edges.push({ source: convNodes[i].id, target: convNodes[i + 1].id, type: "temporal" })
    }
  }

  // Activity heartbeat — how many research jobs are in flight (drives smart polling)
  const activeResearch = (research ?? []).filter(j => j.status === "queued" || j.status === "running").length

  return NextResponse.json({ nodes, edges, activeResearch })
}
