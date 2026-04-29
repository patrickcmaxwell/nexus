export const runtime = "nodejs"

import { NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { USER_ID } from "@/lib/operations/auth"
import type { MentionResult, MentionType } from "@/lib/mentions/types"

// GET /api/mentions/search?q=arco&types=operation,record,conversation,topic,agent
//
// Returns a small, ranked list of mentionable entities for the picker.
// Matching is case-insensitive substring on the primary name/title of each
// type. If `q` is empty we still return recent items per type so the picker
// is immediately useful when the user first hits `@`.
export async function GET(req: Request) {
  const url = new URL(req.url)
  const q = (url.searchParams.get("q") ?? "").trim()
  const typesParam = url.searchParams.get("types")
  const requested: MentionType[] = typesParam
    ? (typesParam.split(",").filter(Boolean) as MentionType[])
    : ["operation", "record", "conversation", "topic", "agent"]

  const supabase = createServiceClient()

  // How many rows per type. Keep tight so the popover stays readable.
  const PER_TYPE = 6

  // Build per-type queries. `ilike` on %q% gives us substring matching,
  // matching either the operation's name, codename, record title, etc.
  async function searchOperations(): Promise<MentionResult[]> {
    let qb = supabase.from("operations")
      .select("id, name, codename, status, updated_at")
      .eq("user_id", USER_ID)
      .order("updated_at", { ascending: false }).limit(PER_TYPE)
    if (q) qb = qb.or(`name.ilike.%${q}%,codename.ilike.%${q}%`)
    const { data } = await qb
    return (data ?? []).map(r => ({
      type: "operation",
      id: r.id as string,
      label: (r.codename as string | null) || (r.name as string),
      sublabel: (r.codename ? (r.name as string) : undefined),
      status: r.status as string | undefined,
    }))
  }
  async function searchRecords(): Promise<MentionResult[]> {
    let qb = supabase.from("operation_records")
      .select("id, title, type, operation_id, updated_at, operations!inner(name, codename)")
      .eq("user_id", USER_ID).eq("archived", false)
      .order("updated_at", { ascending: false }).limit(PER_TYPE)
    if (q) qb = qb.ilike("title", `%${q}%`)
    const { data } = await qb
    return (data ?? []).map((r: unknown) => {
      const row = r as Record<string, unknown>
      const op = row.operations as Record<string, unknown> | null
      const opLabel = op ? ((op.codename as string | null) || (op.name as string) || "") : ""
      return {
        type: "record" as const,
        id: row.id as string,
        label: row.title as string,
        sublabel: `${row.type ?? "record"}${opLabel ? ` · ${opLabel}` : ""}`,
      }
    })
  }
  async function searchConversations(): Promise<MentionResult[]> {
    let qb = supabase.from("eve_conversations")
      .select("id, title, updated_at")
      .eq("user_id", USER_ID)
      .order("updated_at", { ascending: false }).limit(PER_TYPE)
    if (q) qb = qb.ilike("title", `%${q}%`)
    const { data } = await qb
    return (data ?? []).map(r => ({
      type: "conversation" as const,
      id: r.id as string,
      label: (r.title as string) || "(untitled session)",
      sublabel: r.updated_at ? new Date(r.updated_at as string).toLocaleDateString() : undefined,
    }))
  }
  async function searchTopics(): Promise<MentionResult[]> {
    let qb = supabase.from("eve_topics")
      .select("id, label, description, color, created_at, eve_conversations!inner(title)")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }).limit(PER_TYPE)
    if (q) qb = qb.ilike("label", `%${q}%`)
    const { data } = await qb
    return (data ?? []).map((r: unknown) => {
      const row = r as Record<string, unknown>
      const conv = row.eve_conversations as Record<string, unknown> | null
      return {
        type: "topic" as const,
        id: row.id as string,
        label: row.label as string,
        sublabel: conv?.title ? `in "${conv.title}"` : undefined,
        color: (row.color as string | undefined) ?? undefined,
      }
    })
  }
  async function searchAgents(): Promise<MentionResult[]> {
    let qb = supabase.from("agents")
      .select("id, name, codename, role, status, created_at")
      .eq("user_id", USER_ID)
      .order("created_at", { ascending: false }).limit(PER_TYPE)
    if (q) qb = qb.or(`name.ilike.%${q}%,codename.ilike.%${q}%,role.ilike.%${q}%`)
    const { data } = await qb
    return (data ?? []).map(r => ({
      type: "agent" as const,
      id: r.id as string,
      label: (r.codename as string | null) || (r.name as string),
      sublabel: r.role as string | undefined,
      status: r.status as string | undefined,
    }))
  }

  const jobs: Array<Promise<MentionResult[]>> = []
  if (requested.includes("operation"))    jobs.push(searchOperations())
  if (requested.includes("record"))       jobs.push(searchRecords())
  if (requested.includes("conversation")) jobs.push(searchConversations())
  if (requested.includes("topic"))        jobs.push(searchTopics())
  if (requested.includes("agent"))        jobs.push(searchAgents())

  try {
    const batches = await Promise.all(jobs)
    const results = batches.flat()
    return NextResponse.json({ results })
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error("[v0] mention search failed:", err)
    return NextResponse.json({ results: [] }, { status: 200 })
  }
}
