import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import { createPartybotServiceClient } from "@/lib/partybot-supabase/service"

// PATCH /api/partybot/bot/[id]
// Owner-gated. Updates a row in partybot's Supabase via service-role client.
//
// Body: a partial PartybotBot — only whitelisted fields below get applied.
// If is_owner_canonical=true is set, also flips other bots' is_owner_canonical
// off (the partial unique index in partybot's migration 020 would reject
// otherwise).

const WHITELIST = new Set([
  "bot_name",
  "archetype",
  "archetype_label",
  "tag",
  "color",
  "sass_mode",
  "bio",
  "custom_prompt",
  "rules",
  "friend_rules",
  "is_owner_canonical",
  "is_public",
])

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "unauthenticated" }, { status: 401 })
  if (!me.isOwner) return NextResponse.json({ error: "owner only" }, { status: 403 })

  const { id } = await ctx.params
  if (!isUuid(id)) return NextResponse.json({ error: "bad id" }, { status: 400 })

  const supabase = createPartybotServiceClient()
  if (!supabase) return NextResponse.json({ error: "partybot supabase not configured" }, { status: 503 })

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: "bad json" }, { status: 400 })
  }

  const patch: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(body)) {
    if (WHITELIST.has(k)) patch[k] = v
  }
  if (Object.keys(patch).length === 0) {
    return NextResponse.json({ error: "no whitelisted fields" }, { status: 400 })
  }
  patch.updated_at = new Date().toISOString()

  // Need the bot's user_id to scope the canonical-flip query.
  const { data: existing, error: getErr } = await supabase
    .from("bots")
    .select("user_id, is_owner_canonical")
    .eq("id", id)
    .single()
  if (getErr || !existing) return NextResponse.json({ error: "bot not found" }, { status: 404 })

  // Flip other bots' canonical flag off before this update, to honor the
  // partial unique index (one canonical per user) in partybot's migration 020.
  if (patch.is_owner_canonical === true && !existing.is_owner_canonical) {
    await supabase
      .from("bots")
      .update({ is_owner_canonical: false })
      .eq("user_id", existing.user_id)
      .neq("id", id)
  }

  const { data: updated, error: updErr } = await supabase
    .from("bots")
    .update(patch)
    .eq("id", id)
    .select()
    .single()

  if (updErr) return NextResponse.json({ error: updErr.message }, { status: 500 })
  return NextResponse.json(updated)
}

function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s)
}
