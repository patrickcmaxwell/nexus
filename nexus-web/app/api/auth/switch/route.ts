// POST /api/auth/switch — swap the active session to a different known user.
// Requires PIN re-verification (security default — cached cookies are not
// trusted for switching). Invalidates the prior session, creates a new one
// for the target human, returns the new cookie.
//
// Body: { email: string, pin: string }
// Resp: { success: true, displayName, role } + sets nx_session cookie
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { getActiveHuman } from "@/lib/auth/session"
import { sessionCookieOptions } from "@/lib/auth/cookie"
import crypto from "crypto"

const COOKIE = "nx_session"
const SESSION_MINUTES = 60 * 24 * 14 // 14 days, matches proxy.ts

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

  const { email, pin } = await req.json()
  if (!email || !pin) {
    return NextResponse.json({ error: "Email and PIN are required" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")

  // Identity-first lookup: find the target human by email, THEN verify PIN.
  // Eliminates the PIN-collision bug from the old single-column lookup.
  const { data: target } = await supabase
    .from("humans")
    .select("id, display_name, role, status, pin_hash")
    .ilike("email", email)
    .single()

  if (!target || target.status !== "active") {
    return NextResponse.json({ error: "User not found" }, { status: 404 })
  }
  if (target.pin_hash !== pinHash) {
    return NextResponse.json({ error: "Invalid PIN" }, { status: 401 })
  }

  // Invalidate the previous session so the user can't accidentally switch
  // back via stale cookie — they'd need to re-auth as themselves anyway.
  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("id", me.sessionId)

  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + SESSION_MINUTES * 60 * 1000).toISOString()
  const { data: session, error: insertErr } = await supabase
    .from("security_sessions")
    .insert({
      user_id: target.id, // text column; we keep it for backward compat
      team_member_id: target.id,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "switch",
      invalidated: false,
    })
    .select("id")
    .single()

  if (insertErr || !session) {
    return NextResponse.json({ error: "Failed to create session" }, { status: 500 })
  }

  const response = NextResponse.json({
    success: true,
    displayName: target.display_name,
    role: target.role,
  })
  response.cookies.set(COOKIE, session.id, sessionCookieOptions({
    maxAgeSeconds: SESSION_MINUTES * 60,
  }))
  return response
}
