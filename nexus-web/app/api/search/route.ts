// /api/search?q=<query>
//
// Unified server-side search across the active human's data. Powers the
// Cmd-K palette in nexus-web. Mirrors LumenLocalDB.search semantics so the
// shape + ranking feel identical between desktop and web.
//
// Why server-side: nexus-web is RSC; we don't ship a client cache. The
// search endpoint runs ILIKE across the same six entity types Lumen
// searches locally. Per-kind row cap keeps the result set scannable.
//
// Auth: scoped to the active human via getActiveAuthId. Returns 401 on
// no session — palette will gray out and prompt re-login.

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"

export const runtime = "nodejs"
// Force-dynamic so the page-data collector doesn't try to evaluate this at
// build time (it would fail without an active session).
export const dynamic = "force-dynamic"

const PER_KIND = 8

export type SearchHit = {
  kind: "conversation" | "operation" | "record" | "agent" | "memory" | "directive"
  id: string
  label: string
  snippet: string
}

export async function GET(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const q = (new URL(req.url).searchParams.get("q") ?? "").trim()
  if (q.length < 1) return NextResponse.json({ hits: [] })

  // Postgres `ilike` pattern — wrap with %% for substring match. Escape any
  // user-supplied % or _ so a search for "50%" doesn't blow up the LIKE.
  const escaped = q.replace(/[%_\\]/g, (m) => `\\${m}`)
  const needle = `%${escaped}%`

  const supabase = createServiceClient()

  // Fire all six queries in parallel — no inter-query dependencies.
  const [convRes, opsRes, recsRes, agentsRes, memsRes, dirsRes] = await Promise.all([
    supabase
      .from("eve_conversations")
      .select("id, title, source, updated_at")
      .eq("user_id", userId)
      .ilike("title", needle)
      .order("updated_at", { ascending: false })
      .limit(PER_KIND),
    supabase
      .from("operations")
      .select("id, name, codename, status, updated_at")
      .eq("user_id", userId)
      .or(`name.ilike.${needle},codename.ilike.${needle}`)
      .order("updated_at", { ascending: false })
      .limit(PER_KIND),
    supabase
      .from("operation_records")
      .select("id, title, content, type, updated_at")
      .eq("user_id", userId)
      .is("archived_at", null)
      .or(`title.ilike.${needle},content.ilike.${needle}`)
      .order("updated_at", { ascending: false })
      .limit(PER_KIND),
    supabase
      .from("agents")
      .select("id, name, codename, role, status")
      .eq("user_id", userId)
      .or(`name.ilike.${needle},codename.ilike.${needle},role.ilike.${needle}`)
      .order("created_at", { ascending: false })
      .limit(PER_KIND),
    supabase
      .from("eve_memory")
      .select("id, content, type, priority")
      .eq("user_id", userId)
      .eq("is_active", true)
      .ilike("content", needle)
      .order("priority", { ascending: false })
      .limit(PER_KIND),
    supabase
      .from("eve_directives")
      .select("id, title, content, type, priority")
      .eq("user_id", userId)
      .eq("is_active", true)
      .or(`title.ilike.${needle},content.ilike.${needle}`)
      .order("priority", { ascending: false })
      .limit(PER_KIND),
  ])

  const hits: SearchHit[] = []

  for (const r of convRes.data ?? []) {
    hits.push({
      kind: "conversation",
      id: r.id as string,
      label: (r.title as string) || "(untitled)",
      snippet: (r.source as string) || "",
    })
  }
  for (const r of opsRes.data ?? []) {
    hits.push({
      kind: "operation",
      id: r.id as string,
      label: (r.codename as string) || (r.name as string) || "(untitled)",
      snippet: r.codename ? (r.name as string) : (r.status as string) || "",
    })
  }
  for (const r of recsRes.data ?? []) {
    const content = ((r.content as string) ?? "").replace(/\s+/g, " ").trim().slice(0, 140)
    hits.push({
      kind: "record",
      id: r.id as string,
      label: (r.title as string) || "(untitled)",
      snippet: content,
    })
  }
  for (const r of agentsRes.data ?? []) {
    hits.push({
      kind: "agent",
      id: r.id as string,
      label: (r.codename as string) || (r.name as string) || "(unnamed)",
      snippet: (r.role as string) || (r.status as string) || "",
    })
  }
  for (const r of memsRes.data ?? []) {
    const content = ((r.content as string) ?? "").replace(/\s+/g, " ").trim()
    hits.push({
      kind: "memory",
      id: r.id as string,
      label: content.slice(0, 80),
      snippet: (r.type as string) ?? "fact",
    })
  }
  for (const r of dirsRes.data ?? []) {
    const content = ((r.content as string) ?? "").replace(/\s+/g, " ").trim().slice(0, 140)
    hits.push({
      kind: "directive",
      id: r.id as string,
      label: (r.title as string) || "(untitled)",
      snippet: content,
    })
  }

  return NextResponse.json({ hits })
}
