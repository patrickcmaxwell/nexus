// PIN authentication — identity-first lookup.
//
// Body shape: { email, pin, remember? }
//
// Why email + PIN: PINs are short and memorable, so collisions across team
// members are inevitable. Looking up by `email` first (then verifying PIN
// hash on that one row) makes PIN-collision a non-issue. The old
// `WHERE pin_hash = ?` lookup picked one row arbitrarily on collision.
//
// Lumen desktop sends `X-Lumen-Client: 1` and gets the sessionId echoed in
// the response body so it can stash the cookie via WKWebView.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"
import { sessionCookieOptions } from "@/lib/auth/cookie"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// GET: probe whether an existing PIN-verified cookie is present (login page
// uses this to skip the PIN step on the same browser within the cookie window).
export async function GET(req: NextRequest) {
  const pinVerified = req.cookies.get("mn_pin_verified")?.value
  if (pinVerified) return NextResponse.json({ verified: true })
  return NextResponse.json({ verified: false }, { status: 401 })
}

export async function POST(req: NextRequest) {
  const { email, pin, remember } = await req.json()

  if (!email || !pin) {
    return NextResponse.json({ error: "Email and PIN required" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")

  // Identity-first: pin down a single row by email, THEN verify hash.
  // Email match is case-insensitive (.ilike treats the value as a pattern,
  // but with no wildcards it's a plain case-insensitive equality).
  const { data: human } = await supabase
    .from("humans")
    .select("id, display_name, role, status, pin_hash")
    .ilike("email", email)
    .single()

  // Distinct error codes so the UI can guide users instead of stonewalling.
  // Email enumeration risk is mitigated by the existing IP rate-limit; the
  // UX gain is worth the trade-off (otherwise users keep trying the wrong
  // email and get blocked thinking it's a system bug).
  if (!human) {
    return NextResponse.json({ error: "UNKNOWN_EMAIL" }, { status: 401 })
  }
  if (human.status === "invited") {
    return NextResponse.json({ error: "INVITE_NOT_ACCEPTED" }, { status: 401 })
  }
  if (human.status === "disabled") {
    return NextResponse.json({ error: "ACCOUNT_LOCKED" }, { status: 401 })
  }
  if (human.status !== "active") {
    return NextResponse.json({ error: "ACCOUNT_INACTIVE" }, { status: 401 })
  }
  if (human.pin_hash !== pinHash) {
    return NextResponse.json({ error: "WRONG_PIN" }, { status: 401 })
  }

  // Successful authentication — create the session row.
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()
  const { data: session } = await supabase
    .from("security_sessions")
    .insert({
      user_id: human.id, // text column, mirrors team_member_id for compat
      team_member_id: human.id,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "pin",
      invalidated: false,
    })
    .select("id")
    .single()

  // Guarantee a sessionId for Lumen even on transient DB hiccup.
  const sessionId = session?.id ?? crypto.randomUUID()
  const isLumenClient = req.headers.get("X-Lumen-Client") === "1"
  const maxAge = remember ? 60 * 60 * 24 * 30 : 60 * 60 * 8

  const body: Record<string, unknown> = {
    success: true,
    displayName: human.display_name,
    role: human.role,
  }
  if (isLumenClient) body.sessionId = sessionId

  const response = NextResponse.json(body)
  response.cookies.set("mn_pin_verified", "1", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    path: "/",
    maxAge,
  })
  // Centralized cookie config — env-aware secure/sameSite + optional
  // SESSION_COOKIE_DOMAIN for subdomain cookie share with arena.
  response.cookies.set("nx_session", sessionId, sessionCookieOptions())
  return response
}

// DELETE — clears auxiliary auth cookies on explicit logout. The main
// nx_session cookie is invalidated server-side via /api/security/logout.
export async function DELETE() {
  const response = NextResponse.json({ success: true })
  response.cookies.delete("mn_pin_verified")
  response.cookies.delete("mn_face_verified")
  response.cookies.delete("nx_pending_member")
  return response
}
