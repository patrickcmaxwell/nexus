// /api/auth/me — get and patch the current human's profile.
//
// GET    — returns identity bundle including avatar_url (used by the
//          dashboard header avatar dropdown and Lumen).
// PATCH  — updates display_name and/or handle. Both are optional. Handle
//          is unique across humans, so a collision returns 409.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { getActiveHuman } from "@/lib/auth/session"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

export async function GET() {
  const human = await getActiveHuman()
  if (!human) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  }
  const supabase = getServiceClient()
  const { data: extra } = await supabase
    .from("humans")
    .select("avatar_url")
    .eq("id", human.humanId)
    .single()
  return NextResponse.json({
    humanId: human.humanId,
    email: human.email,
    displayName: human.displayName,
    handle: human.handle,
    role: human.role,
    isOwner: human.isOwner,
    authMethod: human.authMethod,
    avatarUrl: extra?.avatar_url ?? null,
  })
}

export async function PATCH(req: NextRequest) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const update: Record<string, unknown> = {}

  if (typeof body.displayName === "string") {
    const trimmed = body.displayName.trim()
    if (trimmed.length < 1 || trimmed.length > 80) {
      return NextResponse.json({ error: "Display name must be 1–80 characters" }, { status: 400 })
    }
    update.display_name = trimmed
  }

  if (body.handle !== undefined) {
    if (body.handle === null || body.handle === "") {
      update.handle = null
    } else if (typeof body.handle === "string") {
      const h = body.handle.trim().toLowerCase().replace(/^@/, "")
      if (!/^[a-z0-9_]{2,30}$/.test(h)) {
        return NextResponse.json({ error: "Handle must be 2–30 chars, lowercase letters/numbers/underscore" }, { status: 400 })
      }
      update.handle = h
    }
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "No supported fields to update" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { error } = await supabase.from("humans").update(update).eq("id", me.humanId)
  if (error) {
    if (error.code === "23505") {
      return NextResponse.json({ error: "That handle is taken" }, { status: 409 })
    }
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
  return NextResponse.json({ success: true })
}
