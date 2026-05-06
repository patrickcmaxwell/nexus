// POST /api/auth/change-pin
//
// Self-service PIN rotation. Authenticated user verifies their CURRENT PIN
// (defense-in-depth — even with a valid session cookie they must prove
// they are the human, in case the device is shared or unattended), then
// the new PIN replaces it on the humans row.
//
// Body: { currentPin: string, newPin: string }
//
// Why this exists: without it, a forgotten/compromised PIN forces an admin
// (Patrick) to reset directly via Supabase. With it, every team member
// manages their own credential without bothering the Director.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { getActiveHuman } from "@/lib/auth/session"
import crypto from "crypto"

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
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  }

  const { currentPin, newPin } = await req.json()
  if (!currentPin || !newPin) {
    return NextResponse.json({ error: "currentPin and newPin are required" }, { status: 400 })
  }
  if (newPin.length < 4) {
    return NextResponse.json({ error: "PIN must be at least 4 digits" }, { status: 400 })
  }
  if (currentPin === newPin) {
    return NextResponse.json({ error: "New PIN must differ from current" }, { status: 400 })
  }

  const supabase = getServiceClient()

  // Re-fetch the row to verify current PIN against the stored hash. We
  // can't trust the cached `me.pin_hash` because getActiveHuman doesn't
  // expose it (and shouldn't — secrets stay server-side).
  const { data: row } = await supabase
    .from("humans")
    .select("pin_hash")
    .eq("id", me.humanId)
    .single()

  if (!row) {
    return NextResponse.json({ error: "User not found" }, { status: 404 })
  }

  const currentHash = crypto.createHash("sha256").update(currentPin).digest("hex")
  if (row.pin_hash !== currentHash) {
    return NextResponse.json({ error: "Current PIN incorrect" }, { status: 401 })
  }

  const newHash = crypto.createHash("sha256").update(newPin).digest("hex")
  const { error: updateErr } = await supabase
    .from("humans")
    .update({ pin_hash: newHash })
    .eq("id", me.humanId)

  if (updateErr) {
    return NextResponse.json({ error: updateErr.message }, { status: 500 })
  }

  // PIN rotation invalidates all OTHER sessions for this human (defense:
  // if someone stole a session cookie before the rotation, they still
  // have it). The current session stays valid — this exact request
  // proves the rotator is in possession of the new credential.
  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("team_member_id", me.humanId)
    .neq("id", me.sessionId)

  return NextResponse.json({ success: true })
}
