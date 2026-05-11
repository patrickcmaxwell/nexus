// POST /api/security/reverify — re-confirm the active human's identity with PIN.
//
// Used by re-auth gates (FaceScanModal, ReAuthGate, NexusPresenceGuard) when
// face verification fails or presence detection lapses. Replaces the old
// /api/passphrase fallback which minted owner sessions for anyone holding
// the shared MAXWELL_PIN — that endpoint was a backdoor and is now disabled.
//
// This route requires:
//   1. A valid (non-invalidated, non-expired) nx_session cookie
//   2. The PIN matching the human attached to that session's team_member_id
//
// On success: bumps last_verified_at and returns 200. Does NOT mint a new
// session — re-auth is presence/freshness only.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"
import { getActiveHuman } from "@/lib/auth/session"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

export async function POST(req: NextRequest) {
  const me = await getActiveHuman()
  if (!me) {
    return NextResponse.json({ error: "NOT_AUTHENTICATED" }, { status: 401 })
  }

  const { pin } = await req.json().catch(() => ({}))
  if (typeof pin !== "string" || pin.length < 4) {
    return NextResponse.json({ error: "PIN_REQUIRED" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { data: human } = await supabase
    .from("humans")
    .select("pin_hash")
    .eq("id", me.humanId)
    .single()

  if (!human?.pin_hash) {
    return NextResponse.json({ error: "PIN_NOT_SET" }, { status: 401 })
  }

  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")
  if (pinHash !== human.pin_hash) {
    return NextResponse.json({ error: "INVALID_PIN" }, { status: 401 })
  }

  await supabase
    .from("security_sessions")
    .update({ last_verified_at: new Date().toISOString() })
    .eq("id", me.sessionId)

  return NextResponse.json({ success: true })
}
