// Invitee onboarding — completes the invite flow.
//
// GET  ?token=...   — validates the token, returns the invitee's display name
// POST { token, pin, faceDescriptor? } — sets the invitee's PIN, face,
//   creates their auth.users row (so they own future data writes), flips
//   humans.status to active, returns a session cookie.
//
// Critical: this is where we wire `humans.auth_id`. Without it, the new
// session helper can't return a usable user_id for data queries when this
// person logs in later.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"

const COOKIE = "nx_session"
const SESSION_DAYS = 14

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// Validate an invite token without consuming it
export async function GET(req: NextRequest) {
  const token = req.nextUrl.searchParams.get("token")
  if (!token) return NextResponse.json({ error: "Missing token" }, { status: 400 })

  const supabase = getServiceClient()
  const { data: human } = await supabase
    .from("humans")
    .select("id, display_name, email, status, seed_face_descriptor")
    .eq("invite_token", token)
    .single()

  if (!human) return NextResponse.json({ error: "Invalid invite token" }, { status: 404 })
  if (human.status !== "invited") {
    return NextResponse.json({ error: "Invite already used" }, { status: 410 })
  }

  return NextResponse.json({
    displayName: human.display_name,
    email: human.email,
    hasSeedFace: !!human.seed_face_descriptor,
  })
}

// Complete onboarding — set PIN, optional face, create auth.users row,
// activate human, return session cookie.
export async function POST(req: NextRequest) {
  const { token, pin, faceDescriptor } = await req.json()

  if (!token || !pin) {
    return NextResponse.json({ error: "Token and PIN are required" }, { status: 400 })
  }
  if (pin.length < 4) {
    return NextResponse.json({ error: "PIN must be at least 4 digits" }, { status: 400 })
  }

  const supabase = getServiceClient()

  const { data: human } = await supabase
    .from("humans")
    .select("id, display_name, email, status")
    .eq("invite_token", token)
    .single()

  if (!human) return NextResponse.json({ error: "Invalid invite token" }, { status: 404 })
  if (human.status !== "invited") {
    return NextResponse.json({ error: "Invite already used" }, { status: 410 })
  }

  // Create the auth.users row so this human owns future data writes.
  // Uses a random password — the user authenticates via PIN + face on the
  // humans row, NOT against auth.users directly. The auth.users row exists
  // purely as the FK target for user_id columns on data tables.
  const randomPassword = crypto.randomBytes(32).toString("hex")
  const { data: created, error: createErr } = await supabase.auth.admin.createUser({
    email: human.email,
    password: randomPassword,
    email_confirm: true,
  })
  if (createErr || !created?.user) {
    console.error("[nexus] auth.users creation failed:", createErr?.message)
    return NextResponse.json({ error: "Failed to provision identity" }, { status: 500 })
  }
  const authUserId = created.user.id

  // Hash the PIN and activate the human row.
  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")
  const { error: updateErr } = await supabase
    .from("humans")
    .update({
      pin_hash: pinHash,
      face_descriptor: faceDescriptor || null,
      auth_id: authUserId,
      status: "active",
      invite_token: null,
    })
    .eq("id", human.id)

  if (updateErr) {
    return NextResponse.json({ error: updateErr.message }, { status: 500 })
  }

  // Create session for the freshly-onboarded human.
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000).toISOString()
  const { data: session } = await supabase
    .from("security_sessions")
    .insert({
      user_id: human.id,
      team_member_id: human.id,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "invite",
      invalidated: false,
    })
    .select("id")
    .single()

  const response = NextResponse.json({
    success: true,
    displayName: human.display_name,
    redirect: "/dashboard",
  })
  if (session?.id) {
    response.cookies.set(COOKIE, session.id, {
      httpOnly: true,
      secure: true,
      sameSite: "none",
      path: "/",
      maxAge: SESSION_DAYS * 24 * 60 * 60,
    })
  }
  return response
}
