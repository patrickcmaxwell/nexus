import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { resolveHumanId } from "@/lib/desktop-auth"

// Authorization model for groups:
//   - GET: returns groups the caller created OR is a member of (no workspace-wide enumeration).
//   - POST: any authenticated human can create a group; creator becomes owner.
//   - PATCH / DELETE: only the creator (`created_by`) may modify or delete a group.
// Prior version returned every group across the workspace and allowed any
// authenticated human to PATCH/DELETE arbitrary groups — that was a multi-
// tenancy hole flagged in the 2026-05-13 security audit.

export async function GET(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()

  // Two scopes union: groups I created, groups I'm a member of.
  // Done as two queries because Supabase REST doesn't compose OR across
  // a join in one call cleanly. De-dupe in JS.
  const [createdRes, memberRes] = await Promise.all([
    supabase
      .from("groups")
      .select(`id, name, description, created_by, created_at, group_members(human_id, joined_at, role, humans(display_name, handle))`)
      .eq("created_by", currentHumanId),
    supabase
      .from("group_members")
      .select(`group_id, groups(id, name, description, created_by, created_at, group_members(human_id, joined_at, role, humans(display_name, handle)))`)
      .eq("human_id", currentHumanId),
  ])

  if (createdRes.error) return NextResponse.json({ error: createdRes.error.message }, { status: 500 })
  if (memberRes.error) return NextResponse.json({ error: memberRes.error.message }, { status: 500 })

  const byId = new Map<string, unknown>()
  for (const g of createdRes.data ?? []) byId.set((g as { id: string }).id, g)
  for (const row of memberRes.data ?? []) {
    const g = (row as { groups?: { id: string } }).groups
    if (g?.id && !byId.has(g.id)) byId.set(g.id, g)
  }
  const groups = Array.from(byId.values()).sort((a, b) => {
    const at = (a as { created_at: string }).created_at
    const bt = (b as { created_at: string }).created_at
    return at < bt ? 1 : at > bt ? -1 : 0
  })

  return NextResponse.json({ groups, currentHumanId })
}

export async function POST(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { name, description } = body
  if (!name) return NextResponse.json({ error: "name is required" }, { status: 400 })
  const supabase = createServiceClient()
  const { data: group, error } = await supabase
    .from("groups")
    .insert({ name, description: description ?? "", created_by: currentHumanId })
    .select()
    .single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  await supabase.from("group_members").insert({ group_id: group.id, human_id: currentHumanId, role: "owner" })
  return NextResponse.json(group)
}

export async function PATCH(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const body = await req.json()
  const { id, name, description } = body
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })

  const supabase = createServiceClient()

  // Ownership check first — only the creator may modify.
  const { data: existing, error: lookupErr } = await supabase
    .from("groups")
    .select("created_by")
    .eq("id", id)
    .single()
  if (lookupErr || !existing) {
    return NextResponse.json({ error: "Group not found" }, { status: 404 })
  }
  if (existing.created_by !== currentHumanId) {
    return NextResponse.json({ error: "Forbidden — only the group creator may modify" }, { status: 403 })
  }

  const updates: Record<string, string> = {}
  if (name) updates.name = name
  if (description !== undefined) updates.description = description
  const { data, error } = await supabase.from("groups").update(updates).eq("id", id).select().single()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

export async function DELETE(req: NextRequest) {
  const currentHumanId = await resolveHumanId(req)
  if (!currentHumanId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 })

  const supabase = createServiceClient()

  // Ownership check first — only the creator may delete.
  const { data: existing, error: lookupErr } = await supabase
    .from("groups")
    .select("created_by")
    .eq("id", id)
    .single()
  if (lookupErr || !existing) {
    return NextResponse.json({ error: "Group not found" }, { status: 404 })
  }
  if (existing.created_by !== currentHumanId) {
    return NextResponse.json({ error: "Forbidden — only the group creator may delete" }, { status: 403 })
  }

  const { error } = await supabase.from("groups").delete().eq("id", id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
