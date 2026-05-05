// Owner-only passphrase fallback. Verifies against MAXWELL_PIN env var,
// resolves to the owner human (humans.is_owner=true), and creates a proper
// session with team_member_id set so the new session helper can return a
// usable identity.
//
// Kept as a separate path from /api/security/pin so the existing soft-reauth
// components (FaceScanModal, ReAuthGate, etc.) keep working without form
// changes. The proper multi-user login flow uses /api/security/pin with
// email+pin.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"

const COOKIE = "nx_session"
const SESSION_DAYS = 14

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { persistSession: false } }
  )
}

export async function POST(req: NextRequest) {
  const { passphrase } = await req.json()
  const correct = process.env.MAXWELL_PIN?.trim()

  if (!correct) {
    return NextResponse.json({ error: "PASSPHRASE_NOT_CONFIGURED" }, { status: 500 })
  }

  const input = (passphrase ?? "").trim()
  if (input.toLowerCase() !== correct.toLowerCase()) {
    return NextResponse.json({ error: "INVALID_PASSPHRASE" }, { status: 401 })
  }

  // Resolve to the owner human so the new session helper can return a real
  // identity. Without team_member_id, downstream routes 401 on auth lookup.
  const supabase = getServiceClient()
  const { data: owner } = await supabase
    .from("humans")
    .select("id, display_name, role")
    .eq("is_owner", true)
    .eq("status", "active")
    .single()

  if (!owner) {
    return NextResponse.json({ error: "OWNER_NOT_FOUND" }, { status: 500 })
  }

  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000).toISOString()
  const { data: session } = await supabase
    .from("security_sessions")
    .insert({
      user_id: owner.id,
      team_member_id: owner.id,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "passphrase",
      invalidated: false,
    })
    .select("id")
    .single()

  const sessionId = session?.id ?? crypto.randomUUID()

  const response = NextResponse.json({
    success: true,
    displayName: owner.display_name,
    role: owner.role,
  })
  response.cookies.set(COOKIE, sessionId, {
    httpOnly: true,
    secure: true,
    sameSite: "none",
    path: "/",
    maxAge: SESSION_DAYS * 24 * 60 * 60,
  })
  return response
}
